#!/usr/bin/env bash
set -euo pipefail

# --- 前置检查 ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少依赖：$1"; exit 1; }; }
need curl
need docker
# 支持 docker compose V2（docker 内置插件），或 docker-compose
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "缺少 docker compose（或 docker-compose）"
  exit 1
fi
need nvidia-smi

# --- 获取 GPU 信息 ---
# 格式（无表头）：NVIDIA A10G, GPU-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
gpu_line=$(nvidia-smi --query-gpu=name,uuid --format=csv,noheader | head -n1)
gpu_name=$(echo "$gpu_line" | cut -d',' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
gpu_uuid=$(echo "$gpu_line" | cut -d',' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ -z "${gpu_name}" || -z "${gpu_uuid}" ]]; then
  echo "无法从 nvidia-smi 获取 GPU 名称或 UUID：$gpu_line"
  exit 1
fi
echo "检测到 GPU：${gpu_name} (${gpu_uuid})"

# --- 获取公网 IP ---
default_ip=$(curl -4 -s https://ifconfig.me || true)
if [[ -z "$default_ip" ]]; then
  echo "无法获取公网 IP 地址，请检查网络连接。"
  exit 1
fi
echo "公网 IP：$default_ip"

announce_tcp="/ip4/${default_ip}/tcp/9000"
announce_ws="/ip4/${default_ip}/ws/tcp/9001"

# --- 组装 DOCKER_COMPUTE_ENVIRONMENTS JSON（内嵌 GPU 名称与 UUID） ---
read -r -d '' DOCKER_JSON <<EOF
[{"socketPath":"/var/run/docker.sock","resources":[{"id":"myGPU","description":"${gpu_name}","type":"gpu","total":1,"init":{"deviceRequests":{"Driver":"nvidia","DeviceIDs":["${gpu_uuid}"],"Capabilities":[["gpu"]]}}},{"id":"disk","total":1}],"storageExpiry":604800,"maxJobDuration":3600,"fees":{"1":[{"feeToken":"0x123","prices":[{"id":"cpu","price":1},{"id":"myGPU","price":3}]}]},"free":{"maxJobDuration":60,"maxJobs":3,"resources":[{"id":"cpu","max":1},{"id":"ram","max":1},{"id":"disk","max":1},{"id":"myGPU","max":1}]}}]
EOF

# --- 备份旧 compose ---
if [[ -f docker-compose.yml ]]; then
  cp docker-compose.yml "docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)"
fi

# --- 生成 docker-compose.yml （替换 IP、GPU 名称、UUID、DOCKER_COMPUTE_ENVIRONMENTS） ---
cat > docker-compose.yml <<YAML
services:
  ocean-node:
    image: oceanprotocol/ocean-node:latest
    pull_policy: always
    container_name: ocean-node
    restart: on-failure
    ports:
      - "8000:8000"
      - "9000:9000"
      - "9001:9001"
      - "9002:9002"
      - "9003:9003"
    environment:
      PRIVATE_KEY: '0x3d486b660ae0610d7d01da1ed5c4b47a6b7c9e954f8996395b98a6e28b6cf889'
      RPCS: '{"1":{"rpc":"https://ethereum-rpc.publicnode.com","fallbackRPCs":["https://rpc.ankr.com/eth","https://1rpc.io/eth","https://eth.api.onfinality.io/public"],"chainId":1,"network":"mainnet","chunkSize":100},"10":{"rpc":"https://mainnet.optimism.io","fallbackRPCs":["https://optimism-mainnet.public.blastapi.io","https://rpc.ankr.com/optimism","https://optimism-rpc.publicnode.com"],"chainId":10,"network":"optimism","chunkSize":100},"137":{"rpc":"https://polygon-rpc.com/","fallbackRPCs":["https://polygon-mainnet.public.blastapi.io","https://1rpc.io/matic","https://rpc.ankr.com/polygon"],"chainId":137,"network":"polygon","chunkSize":100},"23294":{"rpc":"https://sapphire.oasis.io","fallbackRPCs":["https://1rpc.io/oasis/sapphire"],"chainId":23294,"network":"sapphire","chunkSize":100},"23295":{"rpc":"https://testnet.sapphire.oasis.io","chainId":23295,"network":"sapphire-testnet","chunkSize":100},"11155111":{"rpc":"https://eth-sepolia.public.blastapi.io","fallbackRPCs":["https://1rpc.io/sepolia","https://eth-sepolia.g.alchemy.com/v2/demo"],"chainId":11155111,"network":"sepolia","chunkSize":100},"11155420":{"rpc":"https://sepolia.optimism.io","fallbackRPCs":["https://endpoints.omniatech.io/v1/op/sepolia/public","https://optimism-sepolia.blockpi.network/v1/rpc/public"],"chainId":11155420,"network":"optimism-sepolia","chunkSize":100}}'
      DB_URL: 'http://typesense:8108/?apiKey=xyz'
      IPFS_GATEWAY: 'https://ipfs.io/'
      ARWEAVE_GATEWAY: 'https://arweave.net/'
      INTERFACES: '["HTTP","P2P"]'
      ALLOWED_ADMINS: '["0x2E6619A7C3Edcb8fe81532b8Af4BAf17fA947Ca0"]'
      CONTROL_PANEL: 'true'
      HTTP_API_PORT: '8000'
      P2P_ENABLE_IPV4: 'true'
      P2P_ENABLE_IPV6: 'false'
      P2P_ipV4BindAddress: '0.0.0.0'
      P2P_ipV4BindTcpPort: '9000'
      P2P_ipV4BindWsPort: '9001'
      P2P_ipV6BindAddress: '::'
      P2P_ipV6BindTcpPort: '9002'
      P2P_ipV6BindWsPort: '9003'
      P2P_ANNOUNCE_ADDRESSES: '["${announce_tcp}", "${announce_ws}"]'
      DOCKER_COMPUTE_ENVIRONMENTS: >-
        ${DOCKER_JSON}
    networks:
      - ocean_network
    volumes:
      - node-sqlite:/usr/src/app/databases
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - typesense

  typesense:
    image: typesense/typesense:26.0
    container_name: typesense
    ports:
      - "8108:8108"
    networks:
      - ocean_network
    volumes:
      - typesense-data:/data
    command: '--data-dir /data --api-key=xyz'

volumes:
  typesense-data:
    driver: local
  node-sqlite:
    driver: local

networks:
  ocean_network:
    driver: bridge
YAML

# --- 显示关键替换结果 ---
echo "compose 已写入：(关键信息)"
echo "  GPU description  = ${gpu_name}"
echo "  GPU DeviceIDs    = ${gpu_uuid}"
echo "  Announce IP      = ${default_ip}"

# --- 预检 & 启动 ---
${COMPOSE} config >/dev/null
${COMPOSE} pull ocean-node typesense
${COMPOSE} up -d

echo "完成：ocean-node & typesense 已启动。"
