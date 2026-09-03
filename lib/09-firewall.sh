persist_iptables() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  elif command -v iptables-save >/dev/null 2>&1; then
    mkdir -p /etc/iptables 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
  fi
}

open_firewall() {
  local ports=("$@")
  [ "${#ports[@]}" = 0 ] && return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    local p
    for p in "${ports[@]}"; do
      ufw allow "${p}/tcp" >/dev/null 2>&1
      ufw allow "${p}/udp" >/dev/null 2>&1
    done
    ok "ufw 已放行端口: ${ports[*]}"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    local p
    for p in "${ports[@]}"; do
      firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1
      firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1
    done
    firewall-cmd --reload >/dev/null 2>&1
    ok "firewalld 已放行端口: ${ports[*]}"
  elif command -v iptables >/dev/null 2>&1 && iptables -L -n >/dev/null 2>&1 \
       && iptables -L INPUT -n 2>/dev/null | grep -q "policy DROP\|DROP"; then
    local p
    for p in "${ports[@]}"; do
      iptables -I INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1
      iptables -I INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1
    done
    persist_iptables
    ok "iptables 已放行端口: ${ports[*]} (已尝试持久化)"
  else
    info "未检测到活动防火墙, 跳过 (若使用云安全组请自行放行: ${ports[*]})"
  fi
}

extra_uninstall_containers() {
  printf '%s\n' caddy-panel sub-server
}
