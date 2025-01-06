#!/bin/bash

# 清屏
clear

# 自动获取公网 IP 地址
default_ip=$(curl -s https://ifconfig.me)
if [[ -z "$default_ip" ]]; then
    echo "无法获取公网 IP 地址，请检查网络连接。"
    exit 1
fi

# 询问需要生成的 yml 文件数量
read -p "请输入需要生成的 yml 文件数量: " yml_count

# 询问容器编号的起始值
read -p "请输入容器编号的起始值（例如，如果输入3，则容器将从 ocean-node-3 开始）: " start_index

# 接收 P2P 绑定的 IP 地址
read -p "请输入 P2P 绑定的 IP 地址（默认: $default_ip）: " ip_address
ip_address=${ip_address:-$default_ip}  # 如果未输入，使用默认值

# 输出确认
echo "P2P 绑定的 IP 地址为: $ip_address"

# 接收 Infura Project ID
read -p "请输入 Infura Project ID (例如：5d9f50e145964c318dac0d6526278993): " infura_id

# 验证 Infura Project ID 格式 (32位字符)
if [[ ! $infura_id =~ ^[a-zA-Z0-9]{32}$ ]]; then
  echo "输入的 Infura Project ID 格式不正确，请确保是 32 位字符。"
  exit 1
fi

# 接收 EVM 钱包地址和私钥
declare -A wallets
echo "请输入 EVM 钱包信息（格式: Wallet 1: Public Key: 0x..., Private Key: 0x...），一行一个："

# 循环接收钱包信息
for ((i = 1; i <= yml_count; i++)); do
  wallet_info=""
  while [[ -z "$wallet_info" ]]; do
    read -p "Wallet $i: " wallet_info
  done
  
  # 使用正则表达式精确提取公钥和私钥，去掉多余的逗号和空格
  public_key=$(echo $wallet_info | grep -oP 'Public Key: 0x[a-fA-F0-9]{40}' | cut -d ' ' -f 3)
  private_key=$(echo $wallet_info | grep -oP 'Private Key: 0x[a-fA-F0-9]{64}' | cut -d ' ' -f 3)
  
  # 检查公钥和私钥是否提取成功
  if [[ -z "$public_key" || -z "$private_key" ]]; then
    echo "输入格式有误，请确保格式为: Wallet X: Public Key: 0x..., Private Key: 0x..."
    exit 1
  fi

  # 将提取到的钱包信息存入数组
  wallets[$i]="Public Key: $public_key, Private Key: $private_key"
done

# 基本端口号
base_port=16010

# 循环生成 yml 文件
for ((i = 0; i < yml_count; i++)); do
  # 计算当前容器编号（从 start_index 开始）
  current_index=$((start_index + i))

  # 计算 HTTP 和 P2P 相关端口
  ocean_http_port=$((base_port + (current_index - 1) * 100))
  p2p_ipv4_tcp_port=$((ocean_http_port + 10))
  p2p_ipv4_ws_port=$((p2p_ipv4_tcp_port + 1))
  p2p_ipv6_tcp_port=$((p2p_ipv4_tcp_port + 2))
  p2p_ipv6_ws_port=$((p2p_ipv4_tcp_port + 3))

  # 计算 Typesense 端口
  typesense_port=$((28208 + (current_index - 1) * 10))

  # 获取对应的钱包地址
  evm_address=$(echo ${wallets[$((i + 1))]} | cut -d ' ' -f 3)

  # 去除 EVM 地址中可能多余的逗号
  evm_address=$(echo $evm_address | sed 's/,$//')

  # 创建对应的文件夹
  folder="ocean$current_index"
  mkdir -p $folder

  # 创建 docker-compose.yml 文件
  cat > $folder/docker-compose.yml <<EOL
services:
  ocean-node:
    image: oceanprotocol/ocean-node:latest
    pull_policy: always
    container_name: ocean-node-$current_index
    restart: on-failure
    ports:
      - "$ocean_http_port:$ocean_http_port"
      - "$p2p_ipv4_tcp_port:$p2p_ipv4_tcp_port"
      - "$p2p_ipv4_ws_port:$p2p_ipv4_ws_port"
      - "$p2p_ipv6_tcp_port:$p2p_ipv6_tcp_port"
      - "$p2p_ipv6_ws_port:$p2p_ipv6_ws_port"
    environment:
      PRIVATE_KEY: '${wallets[$((i + 1))]#*, Private Key: }'
      P2P_ANNOUNCE_ADDRESSES: '["/ip4/$ip_address/tcp/$p2p_ipv4_tcp_port", "/ip4/$ip_address/ws/tcp/$p2p_ipv4_ws_port"]'
EOL

  echo "已生成文件: $folder/docker-compose.yml"
done

# 确保用户输入 yes 或 no 之前不会跳过
while true; do
  read -p "是否执行生成的 yml 文件？(yes/no): " execute_choice
  case $execute_choice in
    [Yy]* )
      # 检查系统上是否有 `docker-compose` 或 `docker compose`
      if command -v docker-compose &> /dev/null; then
        docker_cmd="docker-compose"
      elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        docker_cmd="docker compose"
      else
        echo "未检测到 docker-compose 或 docker compose，无法继续执行。"
        exit 1
      fi

      for ((i = 0; i < yml_count; i++)); do
        current_index=$((start_index + i))
        folder="ocean$current_index"
        cd $folder
        echo "正在使用 $docker_cmd up -d 在文件夹: $folder"
        $docker_cmd up -d
        cd ..
      done
      echo "所有 yml 文件已执行完毕。"
      break
      ;;
    [Nn]* )
      echo "yml 文件已生成，但未执行。"
      break
      ;;
    * )
      echo "请输入 'yes' 或 'no'。"
      ;;
  esac
done
