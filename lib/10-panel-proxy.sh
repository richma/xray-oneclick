gen_panel_caddyfile() {
  local out="$1" dom="$2" pport="$3" wport="$4" gw="$5" pass="${6:-}"
  {
    echo "{"
    echo "	auto_https disable_redirects"
    echo "	key_type p256"
    echo "}"
    echo ""
    echo "\$DOMAIN:8443 {"
    echo "	tls {"
    echo "		issuer acme {"
    echo "			disable_tlsalpn_challenge"
    echo "		}"
    echo "	}"
    echo "	root * /srv/www"
    echo "	file_server"
    echo "	encode gzip zstd"
    echo "	header Server \"nginx\""
    echo "}"
    echo ""
    echo "$dom:$pport {"
    echo "	tls {"
    echo "		issuer acme {"
    echo "			disable_tlsalpn_challenge"
    echo "		}"
    echo "	}"
    if [ -n "$pass" ]; then
      local hash
      hash="$(docker run --rm caddy:2 caddy hash-password --plaintext "$pass" 2>/dev/null)"
      [ -n "$hash" ] || die "生成密码哈希失败"
      echo "	basic_auth {"
      echo "		admin $hash"
      echo "	}"
    fi
    echo "	reverse_proxy $gw:$wport"
    echo "}"
  } > "$out"
}

cmd_panel_proxy() {
  check_root
  [ -n "${DOMAIN_ARG:-}" ] || die "需要 -d 指定域名: bash install.sh panel-proxy -d panel.example.com"
  command -v docker >/dev/null 2>&1 || die "Docker 未安装, 请先执行 install"
  docker ps -a --format '{{.Names}}' | grep -qx "3x-ui" || die "3X-UI 面板未安装, 请先执行 install"

  local line port container data_dir
  line="$(grep -v '^#' "$NODES_FILE" 2>/dev/null | grep "|${DOMAIN_ARG}$" | head -1)"
  if [ -n "$line" ]; then
    port="$(echo "$line" | cut -d'|' -f1)"
    container="$(echo "$line" | cut -d'|' -f2)"
    data_dir="$(echo "$line" | cut -d'|' -f4)"
    info "模式A: 复用前端节点 $container (端口 $port) 的 Caddy (域名 $DOMAIN_ARG)"
    docker ps --format '{{.Names}}' | grep -qx "$container" || die "前端节点 $container 未运行"

    local envs uuid network dest sn domain email proxy shortids minver gw
    envs="$(docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}')"
    uuid="$(echo "$envs" | sed -n 's/^UUID=//p' | head -1)"
    network="$(echo "$envs" | sed -n 's/^NETWORK=//p' | head -1)"
    dest="$(echo "$envs" | sed -n 's/^DEST=//p' | head -1)"
    sn="$(echo "$envs" | sed -n 's/^SERVERNAMES=//p' | head -1)"
    domain="$(echo "$envs" | sed -n 's/^DOMAIN=//p' | head -1)"
    email="$(echo "$envs" | sed -n 's/^ACME_EMAIL=//p' | head -1)"
    proxy="$(echo "$envs" | sed -n 's/^PROXY=//p' | head -1)"
    shortids="$(echo "$envs" | sed -n 's/^SHORTIDS=//p' | head -1)"
    minver="$(echo "$envs" | sed -n 's/^MIN_CLIENT_VER=//p' | head -1)"
    gw="$(docker inspect "$container" --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' | head -1)"
    [ -n "$gw" ] || gw="172.17.0.1"
    [ -n "$network" ] || network="tcp"
    [ -n "$uuid" ] || uuid="$(node_field "$data_dir/data/reality_config_info.txt" uuid)"

    gen_panel_caddyfile "$data_dir/Caddyfile" "$DOMAIN_ARG" "$PANEL_PROXY_PORT" "$XUI_PORT" "$gw" "$PANEL_PROXY_PASS"
    ok "Caddyfile 已生成: $data_dir/Caddyfile (含面板反代站点)"

    SHORTIDS="$shortids" MIN_CLIENT_VER="$minver" \
    NODE_CADDYFILE="$data_dir/Caddyfile" \
    NODE_EXTRA_PORTS="$PANEL_PROXY_PORT:$PANEL_PROXY_PORT" \
      run_reality_container "$port" "$network" "$dest" "$sn" "$domain" "$email" "$proxy" "$uuid"
    open_firewall "$PANEL_PROXY_PORT"
    ok "面板 HTTPS 反代已启用: https://$DOMAIN_ARG:$PANEL_PROXY_PORT/<面板路径>/"
    warn "要求: 域名 A 记录已指向本机, 云防火墙放行 TCP $PANEL_PROXY_PORT (证书由前端 Caddy 自动签发/续期)"
    return 0
  fi

  warn "未找到使用域名 $DOMAIN_ARG 的前端节点, 使用独立 Caddy 容器 (需宿主机 80 空闲)"
  local xuidir="$INSTALL_DIR/3x-ui"
  mkdir -p "$xuidir/caddy"
  {
    echo "$DOMAIN_ARG:$PANEL_PROXY_PORT {"
    if [ -n "$PANEL_PROXY_PASS" ]; then
      local hash2
      hash2="$(docker run --rm caddy:2 caddy hash-password --plaintext "$PANEL_PROXY_PASS" 2>/dev/null)"
      [ -n "$hash2" ] || die "生成密码哈希失败"
      echo "    basic_auth {"
      echo "        admin $hash2"
      echo "    }"
    fi
    echo "    reverse_proxy 127.0.0.1:$XUI_PORT"
    echo "}"
  } > "$xuidir/caddy/Caddyfile"
  ok "Caddyfile 已生成: $xuidir/caddy/Caddyfile"

  info "拉取 Caddy 镜像 ..."
  ensure_image "caddy:2"
  docker rm -f caddy-panel >/dev/null 2>&1 || true
  info "启动 Caddy 容器 (--network host, 80 用于 ACME 签发证书) ..."
  docker run -d --name caddy-panel --restart=unless-stopped --network host \
    -v "$xuidir/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
    -v caddy_data:/data -v caddy_config:/config \
    caddy:2 || die "Caddy 启动失败: docker logs caddy-panel"
  open_firewall 80 "$PANEL_PROXY_PORT"
  ok "面板 HTTPS 反代已启用: https://$DOMAIN_ARG:$PANEL_PROXY_PORT/<面板路径>/"
  warn "要求: 域名 A 记录已指向本机 IP, 且云防火墙放行 TCP 80 与 $PANEL_PROXY_PORT (证书由 Caddy 自动签发/续期)"
}
