#!/bin/bash

# 清屏
clear

# 接收用户输入的编号范围
read -p "请输入需要更新的编号范围（例如 1,2-5,8,10）: " input_ranges

expand_ranges() {
  local ranges="$1"
  local expanded=()
  IFS=',' read -ra parts <<< "$ranges"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      expanded+=("$part")
    elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do
        expanded+=("$i")
      done
    else
      echo "[ERROR] 无效的输入范围: $part"
      exit 1
    fi
  done
  echo "${expanded[@]}"
}

process_container() {
  index="$1"
  folder="ocean$index"
  yml_file="$folder/docker-compose.yml"

  if [[ -d "$folder" && -f "$yml_file" ]]; then
    echo "[INFO] 开始处理 $folder..."
    ocean_node_container="ocean-node-$index"
    typesense_container="typesense-$index"
    docker rm -f "$ocean_node_container" "$typesense_container" >/dev/null 2>&1

    cd "$folder"
    if command -v docker-compose &> /dev/null; then
      docker-compose up -d
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
      docker compose up -d
    else
      echo "[ERROR] 未检测到 docker-compose 或 docker compose，无法启动容器。"
      exit 1
    fi
    cd - >/dev/null
    echo "[INFO] 成功更新并重启容器：ocean$index"
  else
    echo "[WARNING] 文件夹 $folder 或文件 $yml_file 不存在，跳过。"
  fi
}

# 展开输入的编号范围
target_indices=($(expand_ranges "$input_ranges"))

# 使用多线程处理
for index in "${target_indices[@]}"; do
  process_container "$index" &
done

# 等待所有后台任务完成
wait

echo "[INFO] 所有操作完成！"
