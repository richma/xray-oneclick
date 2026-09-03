apply_sysctl() {
  [ "${ENABLE_BBR:-1}" = 0 ] && { info "已跳过 BBR 与内核优化"; return 0; }
  mkdir -p "$INSTALL_DIR/conf"
  if [ -f "$SCRIPT_DIR/conf/sysctl-xray.conf" ]; then
    cp -f "$SCRIPT_DIR/conf/sysctl-xray.conf" "$SYSCTL_CONF"
  elif [ ! -f "$SYSCTL_CONF" ]; then
    cat > "$SYSCTL_CONF" <<'SYSCTL_EMBEDDED'
# 与 conf/sysctl-xray.conf 保持同步 (install.sh 内嵌副本)
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.ip_forward = 1
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
vm.swappiness = 10
SYSCTL_EMBEDDED
  fi

  if ! cp -f "$SYSCTL_CONF" "$SYSCTL_FILE" 2>/dev/null; then
    warn "无法写入 $SYSCTL_FILE (无权限?), 内核优化未应用"
    return 1
  fi
  sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || warn "部分 sysctl 参数未生效 (内核不支持时属正常)"
  ok "内核参数优化已应用 ($SYSCTL_FILE)"
}

enable_bbr() {
  [ "${ENABLE_BBR:-1}" = 0 ] && return 0
  if [ ! -w "$SYSCTL_FILE" ]; then
    warn "无法写入 $SYSCTL_FILE, 跳过 BBR 配置"
    return 1
  fi
  if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
    ok "BBR 已启用 (tcp_congestion_control=bbr)"
    return 0
  fi
  if ! modprobe tcp_bbr 2>/dev/null && ! grep -qw tcp_bbr /proc/modules 2>/dev/null; then
    warn "内核不支持 tcp_bbr 模块 (OpenVZ/LXC 或旧内核), 跳过 BBR"
    return 1
  fi
  {
    echo ""
    echo "# BBR (由 install.sh 追加)"
    echo "net.core.default_qdisc = fq"
    echo "net.ipv4.tcp_congestion_control = bbr"
  } >> "$SYSCTL_FILE"
  sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true
  if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
    ok "BBR 已启用: 队列 fq + 拥塞控制 bbr"
  else
    sed -i 's/^net.core.default_qdisc = fq$/net.core.default_qdisc = fq_codel/' "$SYSCTL_FILE" 2>/dev/null
    sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true
    if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
      ok "BBR 已启用 (fq 不可用, 回退 fq_codel)"
    else
      warn "BBR 启用失败, 当前拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    fi
  fi
}
