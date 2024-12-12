#!/bin/bash

# 清屏
clear

echo "[INFO] 开始检查所有 ocean-node-* 容器的日志..."

# 获取所有 ocean-node-* 容器的名称
ocean_node_containers=$(docker ps --format "{{.Names}}" | grep -E "^ocean-node-[0-9]+$")

# 定义处理函数
process_container() {
  ocean_node_container=$1
  container_number=$(echo "$ocean_node_container" | grep -oE "[0-9]+$")
  typesense_container="typesense-$container_number"

  # 获取日志的最后一行
  last_log=$(docker logs --tail 1 "$ocean_node_container" 2>/dev/null)

  # 检查日志是否包含关键字
  if echo "$last_log" | grep -q "republishStoredDDOS()"; then
    echo "[INFO] $ocean_node_container 日志包含关键字，开始重启相关容器..."
    
    # 重启 ocean-node 和 typesense 容器
    docker restart "$ocean_node_container" >/dev/null 2>&1 && echo "  - $ocean_node_container 已成功重启" || echo "  - [ERROR] 无法重启 $ocean_node_container"
    docker restart "$typesense_container" >/dev/null 2>&1 && echo "  - $typesense_container 已成功重启" || echo "  - [ERROR] 无法重启 $typesense_container"
  else
    echo "[INFO] $ocean_node_container 日志未匹配，无需操作。"
  fi
}

export -f process_container  # 导出函数以便 GNU Parallel 使用

# 使用 GNU Parallel 并行处理
echo "$ocean_node_containers" | parallel -j 4 process_container  # 调整 `-j` 的值来设置并行度

echo "[INFO] 操作完成！"
