# Reality 节点: 注册表 / 端口 / 容器 / 状态解析 / vless 链接与订阅
save_node() {
  local port="$1" container="$2" network="$3" data_dir="$4" domain="${5:-}"
  touch "$NODES_FILE"
  grep -v "^${port}|" "$NODES_FILE" > "$NODES_FILE.tmp" 2>/dev/null || true
  echo "${port}|${container}|${network}|${data_dir}|${domain}" >> "$NODES_FILE.tmp"
  mv "$NODES_FILE.tmp" "$NODES_FILE"
}

remove_node() {
  grep -v "^${1}|" "$NODES_FILE" > "$NODES_FILE.tmp" 2>/dev/null || true
  mv "$NODES_FILE.tmp" "$NODES_FILE"
}

node_containers() {
  awk -F'|' '!/^#/ && NF>=2 {print $2}' "$NODES_FILE" 2>/dev/null
}

container_name_for() {
  [ "$1" = "443" ] && echo "xray_reality" || echo "xray_reality_$1"
}

# check_port_free <port> [占用该端口的合法容器名]
check_port_free() {
  local port="$1" name="${2:-}"
  command -v ss >/dev/null 2>&1 || return 0
  [ -n "$name" ] || name="$(container_name_for "$port")"
  if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    return 0
  fi
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
    die "端口 $port 已被占用, 请更换端口 (-p <端口>)"
  fi
}

# 回滚: 删除失败的新容器, 还原被覆盖的真值文件, 再把暂存的旧容器换回来
restore_node_container() {
  local had_old="$1" name="$2" old="$3" bak="$4" data_dir="$5" reason="$6" f
  docker rm -f "$name" >/dev/null 2>&1 || true
  if [ "$had_old" != 1 ]; then
    die "$reason, 且没有可回滚的旧容器; 请查看: docker logs $name"
  fi
  for f in reality_state.json reality_config_info.txt; do
    [ -f "$bak/$f" ] && cp -a "$bak/$f" "$data_dir/$f" 2>/dev/null || true
  done
  docker rename "$old" "$name" 2>/dev/null \
    || die "$reason; 旧容器仍在 $old, 请手工恢复: docker rename $old $name && docker start $name"
  docker start "$name" >/dev/null 2>&1 \
    || die "$reason; 旧容器 $name 已换回但启动失败, 请查看: docker logs $name"
  rm -rf "$bak"
  die "$reason, 已回滚旧容器 $name (配置与密钥已还原); 请先排查失败原因再重试"
}

run_reality_container() {
  local port="$1" network="$2" dest="${3:-www.apple.com:443}" sn="${4:-images.apple.com www.apple.com}"
  local domain="${5:-}" email="${6:-}" proxy="${7:-}" uuid_opt="${8:-}"
  local name node_dir
  name="$(container_name_for "$port")"
  node_dir="$INSTALL_DIR/nodes/node_$port"
  mkdir -p "$node_dir/data"

  ensure_base_files
  [ -f "$TEMPLATE_JSON" ] || die "配置文件模板缺失: $TEMPLATE_JSON"

  cat > "$node_dir/entrypoint-wrapper.sh" <<'WRAPPER_EOF'
#!/bin/sh
# 由 install.sh 生成: 注入增强路由配置模板 (v2ray-rules-dat) 后执行镜像原始入口
cp -f /config.template.json /config.json
exec /entrypoint.sh
WRAPPER_EOF
  chmod +x "$node_dir/entrypoint-wrapper.sh"

  [ -s "$RULES_DIR/geoip.dat" ] || download_rules

  info "拉取 Reality 镜像 $REALITY_IMAGE ..."
  ensure_image "$REALITY_IMAGE"

  local args=(
    -d --name "$name" --restart=always
    --log-opt max-size=100m --log-opt max-file=3
    --entrypoint /entrypoint-wrapper.sh
    -p "$port:443"
    -e EXTERNAL_PORT="$port"
    -e NETWORK="$network"
    -e DEST="$dest"
    -e SERVERNAMES="$sn"
    -e HIDE_SENSITIVE_INFO=true
  )
  [ -n "$uuid_opt" ] && args+=(-e UUID="$uuid_opt")
  [ -n "${SHORTIDS:-}" ] && args+=(-e SHORTIDS="$SHORTIDS")
  [ -n "${MIN_CLIENT_VER:-}" ] && args+=(-e MIN_CLIENT_VER="$MIN_CLIENT_VER")
  if [ -n "$domain" ]; then
    info "域名 self-steal 模式: $domain (容器将自动签发证书并托管站点)"
    args+=(-p 80:80 -e DOMAIN="$domain")
    [ -n "$email" ] && args+=(-e ACME_EMAIL="$email")
  fi
  [ -n "$proxy" ] && args+=(-e PROXY="$proxy")
  args+=(
    -v "$node_dir/data:/data"
    -v "$TEMPLATE_JSON:/config.template.json:ro"
    -v "$node_dir/entrypoint-wrapper.sh:/entrypoint-wrapper.sh:ro"
  )
  if [ -f "$RULES_DIR/geoip.dat" ]; then
    args+=(-v "$RULES_DIR/geoip.dat:/geoip.dat:ro")
  else
    warn "未找到 $RULES_DIR/geoip.dat, 使用镜像内置 geoip 规则"
  fi
  if [ -f "$RULES_DIR/geosite.dat" ]; then
    args+=(-v "$RULES_DIR/geosite.dat:/geosite.dat:ro")
  else
    warn "未找到 $RULES_DIR/geosite.dat, 使用镜像内置 geosite 规则"
  fi

  if [ -n "${NODE_CADDYFILE:-}" ] && [ -f "$NODE_CADDYFILE" ]; then
    info "挂载自定义 Caddyfile: $NODE_CADDYFILE"
    args+=(-v "$NODE_CADDYFILE:/etc/caddy/Caddyfile:ro")
  fi
  # NODE_EXTRA_PORTS 约定一律 host:container; 裸端口数字自动扩成 $pp:$pp
  if [ -n "${NODE_EXTRA_PORTS:-}" ]; then
    local pp mapped
    for pp in $NODE_EXTRA_PORTS; do
      case "$pp" in
        *:*) mapped="$pp" ;;
        *)   mapped="$pp:$pp" ;;
      esac
      info "额外发布端口: $mapped"
      args+=(-p "$mapped")
    done
  fi

  args+=("$REALITY_IMAGE")

  # 旧容器先停+改名暂存: 新容器起不来时可以原样回滚, 不再"先删后建"
  local old="${name}.old" had_old=0
  local data_dir="$node_dir/data" bak_dir="$node_dir/.rollback"
  docker rm -f "$old" >/dev/null 2>&1 || true
  rm -rf "$bak_dir"; mkdir -p "$bak_dir"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    had_old=1
    # 新容器会就地覆盖这两个真值文件, 回滚时必须还原, 否则旧容器的密钥与链接不一致
    local f
    for f in reality_state.json reality_config_info.txt; do
      [ -f "$data_dir/$f" ] && cp -a "$data_dir/$f" "$bak_dir/$f"
    done
    docker stop "$name" >/dev/null 2>&1 || true
    docker rename "$name" "$old" || die "无法暂存旧容器 $name, 已中止 (旧容器未改动)"
  fi

  info "启动 Reality 节点容器: $name (端口 $port / $network) ..."
  if ! docker run "${args[@]}"; then
    restore_node_container "$had_old" "$name" "$old" "$bak_dir" "$data_dir" "容器启动失败"
  fi

  if ! wait_node_ready "$name" "$node_dir/data/reality_config_info.txt"; then
    docker rm -f "$name" >/dev/null 2>&1 || true
    restore_node_container "$had_old" "$name" "$old" "$bak_dir" "$data_dir" "新容器未就绪"
  fi
  [ "$had_old" = 1 ] && docker rm -f "$old" >/dev/null 2>&1 || true
  rm -rf "$bak_dir"
  secure_node_secrets "$node_dir"
  save_node "$port" "$name" "$network" "$node_dir" "$domain"
  update_subscription
  show_node_card "$node_dir"
}

wait_node_ready() {
  local name="$1" info_file="$2" i
  for i in $(seq 1 60); do
    if [ -s "$info_file" ]; then
      chmod 600 "$info_file" 2>/dev/null || true
      return 0
    fi
    if ! docker ps --filter "name=^/${name}$" --format '{{.Names}}' | grep -qx "$name"; then
      warn "容器 $name 已退出, 请查看日志: docker logs $name"
      return 1
    fi
    sleep 2
  done
  warn "等待 $name 生成配置超时, 可稍后执行: bash install.sh info"
}

# 节点数据目录含 Reality 私钥(reality_state.json), 收紧到 root-only
secure_node_secrets() {
  local node_dir="$1"
  chmod 700 "$node_dir/data" 2>/dev/null || true
  chmod 600 "$node_dir/data/reality_state.json" 2>/dev/null || true
  chmod 600 "$node_dir/data/reality_config_info.txt" 2>/dev/null || true
}

# 镜像在 HIDE_SENSITIVE_INFO=true 时会把 info 文件里的 uuid/密钥打码,
# 真值落在同目录 reality_state.json, 这里作为回退来源
node_state_field() {
  local info_file="$1" key="$2" state
  state="$(dirname "$info_file")/reality_state.json"
  [ -s "$state" ] || return 0
  sed -n "s/.*\"${key}\":\"\([^\"]*\)\".*/\1/p" "$state" | head -1
}

node_field() {
  local info_file="$1" field="$2"
  case "$field" in
    uuid)
      local v
      v="$(sed -n 's/^UUID: //p' "$info_file" | head -1)"
      case "$v" in *'*'*) v="" ;; esac
      [ -n "$v" ] || v="$(node_state_field "$info_file" uuid)"
      echo "$v" ;;
    dest)      sed -n 's/^DEST: //p' "$info_file" | head -1 ;;
    port)      sed -n 's/^PORT: //p' "$info_file" | head -1 ;;
    servernames) sed -n 's/^SERVERNAMES: //p' "$info_file" | head -1 | sed 's/ (.*$//' ;;
    pub)
      local pk
      pk="$(sed -n 's/^PUBLICKEY\/PASSWORD: //p' "$info_file" | head -1)"
      case "$pk" in *'*'*) pk="" ;; esac
      [ -n "$pk" ] || pk="$(node_state_field "$info_file" public_key)"
      echo "$pk" ;;
    net)       sed -n 's/^NETWORK: //p' "$info_file" | head -1 ;;
    shortid)   sed -n 's/^SHORTID: //p' "$info_file" | head -1 | awk '{print $1}' ;;
    xhttp_path) sed -n 's/^XHTTP_PATH: //p' "$info_file" | head -1 ;;
    *) echo "" ;;
  esac
}

build_vless_link() {
  local node_dir="$1" ip="$2"
  local info_file="$node_dir/data/reality_config_info.txt"
  [ -f "$info_file" ] || return 1
  local uuid dest sn pub net ext shortid xhttp_path sid_param
  uuid="$(node_field "$info_file" uuid)"
  pub="$(node_field "$info_file" pub)"
  sn="$(node_field "$info_file" servernames)"
  net="$(node_field "$info_file" net)"
  ext="$(node_field "$info_file" port)"
  shortid="$(node_field "$info_file" shortid)"
  xhttp_path="$(node_field "$info_file" xhttp_path)"
  [ -z "$uuid" ] || [ -z "$pub" ] && return 1
  [ -z "$sn" ] && sn="www.apple.com"
  [ -z "$ext" ] && ext="${REALITY_PORT:-443}"
  [ -z "$net" ] && net="tcp"
  [ -n "$shortid" ] && sid_param="&sid=$shortid"
  local first_sn="${sn%% *}"
  if [ "$net" = "xhttp" ]; then
    [ -n "$xhttp_path" ] || xhttp_path="/"
    echo "vless://${uuid}@${ip}:${ext}?encryption=none&security=reality&type=xhttp&sni=${first_sn}&fp=firefox&pbk=${pub}${sid_param}&path=${xhttp_path}&mode=auto#${ip}-reality-xhttp"
  else
    echo "vless://${uuid}@${ip}:${ext}?encryption=none&security=reality&type=tcp&sni=${first_sn}&fp=firefox&pbk=${pub}${sid_param}&flow=xtls-rprx-vision#${ip}-reality-vision"
  fi
}

update_subscription() {
  local link ip
  : > "$SUB_FILE"
  while IFS='|' read -r port container network data_dir domain; do
    [ -n "$port" ] || continue
    [ -n "$container" ] || continue
    local info_file="$data_dir/data/reality_config_info.txt"
    [ -f "$info_file" ] || continue
    if grep -q "vless://" "$info_file"; then
      # HIDE_SENSITIVE_INFO 下若链接被打码(含 *), 丢弃并回退到自行拼装
      while IFS= read -r raw_link; do
        case "$raw_link" in
          *'*'*) continue ;;
          *) printf '%s\n' "$raw_link" >> "$SUB_FILE" ;;
        esac
      done <<< "$(grep -o 'vless://[^#]*' "$info_file" | sort -u)"
    else
      ip="$(curl -4 -sSL --connect-timeout 5 --retry 1 ip.sb 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
      [ -z "$ip" ] && ip="YOUR_SERVER_IP"
      link="$(build_vless_link "$data_dir" "$ip")" && echo "$link" >> "$SUB_FILE"
    fi
  done < "$NODES_FILE"
  if [ -s "$SUB_FILE" ]; then
    chmod 600 "$SUB_FILE" 2>/dev/null || true
    ok "订阅链接已汇总: $SUB_FILE"
  fi
}

show_node_card() {
  local node_dir="$1"
  local info_file="$node_dir/data/reality_config_info.txt"
  if [ -s "$info_file" ]; then
    banner "══════════ 节点配置信息 (含二维码) ══════════"
    sed 's/^PRIVATEKEY: .*/PRIVATEKEY: ******** (已隐藏, 真值在 data\/reality_state.json)/' "$info_file"
    banner "════════════════════════════════════════════"
  fi
}
