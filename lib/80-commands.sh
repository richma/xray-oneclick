cmd_install() {
  check_root
  detect_os
  detect_arch
  detect_virt
  check_network
  ensure_base_files

  banner ""
  banner "╔═══════════════════════════════════════════════════════════════╗"
  banner "║   Xray Reality (Docker) + 3X-UI 一键安装 v${VERSION}            ║"
  banner "╚═══════════════════════════════════════════════════════════════╝"
  banner ""
  info "前置 Reality 容器 与 3X-UI 面板入站是两套节点: 前者由本脚本管理, 后者在面板里配置"

  if [ "${ENABLE_BBR:-1}" = 1 ]; then
    ask_yn "是否启用 BBR + 内核网络优化?" "y"
    [ "$ANSWER" = "n" ] && ENABLE_BBR=0
  fi
  apply_sysctl
  enable_bbr

  if [ "${INSTALL_DOCKER:-1}" = 1 ] && ! command -v docker >/dev/null 2>&1; then
    ask_yn "是否安装 Docker?" "y"
    [ "$ANSWER" = "n" ] && INSTALL_DOCKER=0
  fi
  install_docker
  setup_docker_mirror
  command -v docker >/dev/null 2>&1 || die "Docker 不可用, 无法继续"

  if [ -z "${DEST_ARG:-}" ] && [ -z "${DOMAIN_ARG:-}" ]; then
    pick_dest
  else
    DEST="${DEST_ARG:-www.apple.com:443}"
    SERVERNAMES="${SERVERNAMES_ARG:-images.apple.com www.apple.com}"
  fi

  if [ -z "${REALITY_PORT:-}" ]; then
    ask "Reality 对外端口" "443"
    REALITY_PORT="$ANSWER"
  fi
  if [ -z "${NETWORK_MODE:-}" ]; then
    ask "网络模式 (tcp=vision / xhttp)" "tcp"
    case "$ANSWER" in
      xhttp) NETWORK_MODE="xhttp" ;;
      *) NETWORK_MODE="tcp" ;;
    esac
  fi
  if [ -z "${DOMAIN_ARG:-}" ]; then
    ask_yn "配置域名 self-steal 伪装 (需要域名已解析到本机)?" "n"
    [ "$ANSWER" = "y" ] && {
      ask "请输入域名" ""; DOMAIN_ARG="$ANSWER"
      ask "ACME 邮箱 (可留空)" ""; ACME_EMAIL_ARG="$ANSWER"
    }
  fi
  if [ -z "${UUID_ARG:-}" ]; then
    local existing_info="$INSTALL_DIR/nodes/node_${REALITY_PORT}/data/reality_config_info.txt"
    if [ -f "$existing_info" ]; then
      UUID_ARG="$(node_field "$existing_info" uuid)"
    fi
  fi
  if [ -z "${UUID_ARG:-}" ]; then
    UUID_ARG="$(gen_uuid)"
    info "已生成 UUID: $UUID_ARG"
  fi

  check_port_free "$REALITY_PORT"
  [ -n "${DOMAIN_ARG:-}" ] && check_port_free 80 "$(container_name_for "$REALITY_PORT")"

  if [ "${INSTALL_3XUI:-1}" = 1 ]; then
    ask_yn "是否安装 3X-UI 管理面板 (订阅/二维码/多节点)?" "y"
    [ "$ANSWER" = "n" ] && INSTALL_3XUI=0
  fi

  if [ "${INSTALL_RULES:-1}" = 1 ]; then
    ask_yn "是否下载 v2ray-rules-dat 加强版路由规则?" "y"
    [ "$ANSWER" = "n" ] && INSTALL_RULES=0
  fi

  if [ "${ASSUME_YES:-0}" != 1 ]; then
    confirm "确认开始安装?" || { info "已取消"; exit 0; }
  fi

  download_rules
  run_reality_container "$REALITY_PORT" "$NETWORK_MODE" "$DEST" "$SERVERNAMES" \
    "$DOMAIN_ARG" "$ACME_EMAIL_ARG" "$PROXY_ARG" "$UUID_ARG"
  install_3xui
  install_cron

  local fw_ports=("$REALITY_PORT")
  [ -n "${DOMAIN_ARG:-}" ] && fw_ports+=(80)
  [ "${INSTALL_3XUI:-0}" = 1 ] && fw_ports+=("$XUI_PORT")
  open_firewall "${fw_ports[@]}"

  banner ""
  banner "══════════════════════════════ 安装完成 ══════════════════════════════"
  ok "Reality 前置节点已启动: 端口 $REALITY_PORT / $NETWORK_MODE (容器, 非面板入站)"
  ok "路由规则: v2ray-rules-dat (Loyalsoldier) + 广告拦截; geosite:cn 在服务端表示从本机 IP 出站"
  [ "${INSTALL_3XUI:-0}" = 1 ] && ok "3X-UI 面板: http://<服务器IP>:$XUI_PORT (信息见 $INSTALL_DIR/3x-ui/info.txt)"
  info "查看节点配置/二维码:  bash install.sh info"
  info "订阅链接汇总:         cat $SUB_FILE"
  info "添加本机更多前置节点: bash install.sh add-node"
  info "主从集群 (多机):      bash install.sh cluster-token / cluster-add-node"
  banner "══════════════════════════════════════════════════════════════════════"
}

cmd_add_node() {
  check_root
  command -v docker >/dev/null 2>&1 || die "请先执行 install 安装基础环境"
  ensure_base_files
  [ -s "$RULES_DIR/geoip.dat" ] || download_rules

  local port
  if [ -z "${REALITY_PORT:-}" ]; then
    local p=8443
    while grep -q "^${p}|" "$NODES_FILE" 2>/dev/null; do p=$((p+1)); done
    ask "新节点端口" "$p"
    REALITY_PORT="$ANSWER"
  fi
  port="$REALITY_PORT"
  check_port_free "$port"

  if [ -n "${DOMAIN_ARG:-}" ]; then
    if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE '[:.]80$'; then
      die "端口 80 已被占用, 同一主机只能有一个域名 self-steal 节点 (或先卸载占用 80 的节点)"
    fi
  fi

  local first_line
  first_line="$(grep -v '^#' "$NODES_FILE" 2>/dev/null | head -1)"
  if [ -n "$first_line" ]; then
    local first_dir; first_dir="$(echo "$first_line" | awk -F'|' '{print $4}')"
    NETWORK_MODE="${NETWORK_MODE:-$(node_field "$first_dir/data/reality_config_info.txt" net)}"
  fi
  NETWORK_MODE="${NETWORK_MODE:-tcp}"

  if [ -z "${DEST_ARG:-}" ] && [ -z "${DOMAIN_ARG:-}" ]; then
    pick_dest
  else
    DEST="${DEST_ARG:-www.apple.com:443}"
    SERVERNAMES="${SERVERNAMES_ARG:-images.apple.com www.apple.com}"
  fi
  [ -z "${UUID_ARG:-}" ] && UUID_ARG="$(gen_uuid)"

  run_reality_container "$port" "$NETWORK_MODE" "$DEST" "$SERVERNAMES" \
    "$DOMAIN_ARG" "$ACME_EMAIL_ARG" "$PROXY_ARG" "$UUID_ARG"
  open_firewall "$port"
  ok "节点添加完成: 端口 $port"
}

cmd_update_rules() {
  check_root
  FORCE_RULES=1 download_rules
  local c
  info "重启 Reality 容器以加载新规则 ..."
  for c in $(node_containers); do
    docker restart "$c" >/dev/null 2>&1 && ok "已重启: $c" || warn "重启失败: $c"
  done
  if docker ps --format '{{.Names}}' | grep -qx "3x-ui"; then
    docker restart 3x-ui >/dev/null 2>&1 && ok "已重启: 3x-ui" || warn "重启 3x-ui 失败"
  fi
  ok "v2ray-rules-dat 更新完成"
}

cmd_info() {
  local port container network data_dir domain
  local has=0
  while IFS='|' read -r port container network data_dir domain; do
    [ -n "$port" ] || continue
    has=1
    banner ""
    banner "────────────── 前置节点 $port (容器: $container) ──────────────"
    if docker ps --format '{{.Names}}' | grep -qx "$container"; then
      ok "状态: 运行中"
    else
      warn "状态: 未运行 (docker logs $container 查看原因)"
    fi
    show_node_card "$data_dir"
  done < "$NODES_FILE"
  if [ "$has" = 1 ]; then
    banner ""
    banner "────────────── 订阅链接汇总 ($SUB_FILE) ──────────────"
    [ -f "$SUB_FILE" ] && cat "$SUB_FILE" || info "(暂无)"
  else
    info "尚未安装任何前置 Reality 节点, 请先执行: bash install.sh install"
  fi
  if docker ps -a --format '{{.Names}}' | grep -qx "3x-ui"; then
    banner ""
    banner "────────────── 3X-UI 面板 (独立于前置节点) ──────────────"
    cat "$INSTALL_DIR/3x-ui/info.txt" 2>/dev/null
  fi
}

cmd_uninstall() {
  check_root
  banner "即将卸载以下组件:"
  local c
  for c in $(node_containers); do echo "  - 节点容器: $c"; done
  docker ps -a --format '{{.Names}}' | grep -qx "3x-ui" && echo "  - 3X-UI 容器"
  for c in $(extra_uninstall_containers); do
    docker ps -a --format '{{.Names}}' | grep -qx "$c" && echo "  - 附加容器: $c"
  done
  echo "  - 定时更新任务 $RULES_CRON"
  echo "  - 内核优化 $SYSCTL_FILE"
  confirm "确定卸载?" || { info "已取消"; exit 0; }

  for c in $(node_containers); do docker rm -f "$c" >/dev/null 2>&1 || true; done
  docker rm -f 3x-ui >/dev/null 2>&1 || true
  for c in $(extra_uninstall_containers); do docker rm -f "$c" >/dev/null 2>&1 || true; done
  docker volume rm caddy_data caddy_config >/dev/null 2>&1 || true
  rm -f "$RULES_CRON"
  if [ -f "$SYSCTL_FILE" ]; then
    rm -f "$SYSCTL_FILE"
    sysctl --system >/dev/null 2>&1 || true
    warn "已删除内核优化配置 $SYSCTL_FILE (重启后完全生效)"
  fi
  ok "容器与系统配置已卸载"

  if confirm "是否删除安装数据目录 $INSTALL_DIR (含节点密钥/订阅/3X-UI 数据)?"; then
    rm -rf "$INSTALL_DIR"
    ok "已删除 $INSTALL_DIR"
  else
    ok "已保留 $INSTALL_DIR (节点密钥与数据)"
  fi

  if confirm "是否同时卸载 Docker?"; then
    case "${OS_ID:-}" in
      debian|ubuntu) apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1 || true ;;
      centos|rocky|almalinux|fedora|rhel) yum remove -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 || true ;;
      alpine) apk del docker >/dev/null 2>&1 || true ;;
      *)
        detect_os 2>/dev/null || true
        case "${OS_ID:-}" in
          debian|ubuntu) apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1 || true ;;
          centos|rocky|almalinux|fedora|rhel) yum remove -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 || true ;;
          alpine) apk del docker >/dev/null 2>&1 || true ;;
        esac
        ;;
    esac
    ok "Docker 已卸载"
  fi
  ok "卸载完成"
}
