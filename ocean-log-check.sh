#!/bin/bash

# 清屏
clear

echo "[INFO] 开始检查所有 ocean-node-* 容器的日志..."

# 获取所有 ocean-node-* 容器的名称
ocean_node_containers=$(docker ps --format "{{.Names}}" | grep -E "^ocean-node-[0-9]+$")

# 定义线程数量
THREADS=4
SEMAPHORE="/tmp/semaphore.$$"

# 初始化信号量文件
mkfifo "$SEMAPHORE"
exec 3<>"$SEMAPHORE"
for ((i=0; i<$THREADS; i++)); do
  echo >&3
done

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

# 遍历容器列表并处理
for ocean_node_container in $ocean_node_containers; do
  # 等待信号量
  read -u 3

  # 启动子进程处理容器
  {
    process_container "$ocean_node_container"
    echo >&3  # 释放信号量
  } &
done

# 等待所有子进程完成
wait

# 清理信号量文件
exec 3>&-
rm -f "$SEMAPHORE"

echo "[INFO] 操作完成！"
