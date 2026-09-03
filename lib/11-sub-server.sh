# 生成订阅服务的 URL 路径片段 (不含开头 /)
sub_server_token_path() {
  local token="${1:-}"
  if [ -z "$token" ]; then
    token="$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c1-16)"
    [ -n "$token" ] || token="$(openssl rand -hex 8 2>/dev/null || echo xosub)"
  fi
  printf '%s' "$token"
}

cmd_sub_server() {
  check_root
  command -v docker >/dev/null 2>&1 || die "Docker 未安装"
  [ -s "$SUB_FILE" ] || die "未找到 $SUB_FILE, 请先安装节点 (install / add-node)"

  local token token_file www
  token_file="$INSTALL_DIR/sub-server.token"
  if [ -n "${SUB_SERVER_TOKEN:-}" ]; then
    token="$(sub_server_token_path "$SUB_SERVER_TOKEN")"
  elif [ -s "$token_file" ]; then
    token="$(tr -d '[:space:]' < "$token_file")"
  else
    token="$(sub_server_token_path)"
  fi
  printf '%s\n' "$token" > "$token_file"
  chmod 600 "$token_file" 2>/dev/null || true

  www="$INSTALL_DIR/sub-www"
  rm -rf "$www"
  mkdir -p "$www/$token"
  cp -f "$SUB_FILE" "$www/$token/subscription.txt"
  chmod 644 "$www/$token/subscription.txt"

  info "拉取 busybox 镜像 ..."
  ensure_image "busybox:latest"
  docker rm -f sub-server >/dev/null 2>&1 || true
  info "启动订阅 HTTP 服务 (端口 $SUB_SERVER_PORT, 随机路径) ..."
  docker run -d --name sub-server --restart=unless-stopped \
    -p "$SUB_SERVER_PORT:80" \
    -v "$www:/www:ro" \
    busybox:latest httpd -f -p 80 -h /www || die "sub-server 启动失败: docker logs sub-server"
  open_firewall "$SUB_SERVER_PORT"
  ok "订阅 HTTP 服务已启动: http://<本机IP>:$SUB_SERVER_PORT/$token/subscription.txt"
  info "路径令牌已写入 $token_file (chmod 600). 不要把该 URL 提交到公开仓库."
  info "用途: 在主节点 3X-UI 面板 -> 外部订阅 中添加该 URL, 聚合此节点的节点列表"
}
