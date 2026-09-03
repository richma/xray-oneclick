download_rules() {
  [ "${INSTALL_RULES:-1}" = 0 ] && { warn "已跳过 v2ray-rules-dat 下载"; return 0; }
  mkdir -p "$RULES_DIR"
  local base="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
  local js="https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release"
  local f ok_all=1
  info "下载 v2ray-rules-dat 规则文件 (geoip.dat / geosite.dat) ..."
  for f in geoip.dat geosite.dat; do
    if [ -s "$RULES_DIR/$f" ] && [ "${FORCE_RULES:-0}" = 1 ]; then rm -f "$RULES_DIR/$f"; fi
    if [ -s "$RULES_DIR/$f" ] && [ -s "$RULES_DIR/$f.sha256sum" ] \
       && (cd "$RULES_DIR" && sha256sum -c "$f.sha256sum" --status 2>/dev/null); then
      ok "规则文件已存在且校验通过: $f"
      continue
    fi
    # 官方 → GitHub 代理 → jsDelivr (不依赖 -m, 国内网络也能兜底)
    # shellcheck disable=SC2046
    if try_download "$RULES_DIR/$f" $(github_release_urls "$base/$f") "$js/$f"; then
      # shellcheck disable=SC2046
      try_download "$RULES_DIR/$f.sha256sum" $(github_release_urls "$base/$f.sha256sum") "$js/$f.sha256sum" || true
    else
      warn "规则文件下载失败: $f"
      ok_all=0
      continue
    fi
    if [ -s "$RULES_DIR/$f.sha256sum" ] \
       && (cd "$RULES_DIR" && sha256sum -c "$f.sha256sum" --status 2>/dev/null); then
      ok "下载并校验通过: $f"
    else
      warn "规则文件校验文件缺失或校验失败 (继续使用已下载文件): $f"
    fi
  done
  [ "$ok_all" = 1 ] && ok "v2ray-rules-dat 就绪 (Loyalsoldier 加强版路由规则)"
}

install_cron() {
  [ "${INSTALL_RULES:-1}" = 0 ] && return 0
  if [ ! -f "$INSTALL_DIR/install.sh" ]; then
    warn "未找到 $INSTALL_DIR/install.sh, 跳过定时更新 (通过 \`bash <(curl)\` 方式运行时可先手动执行 update-rules)"
    return 0
  fi
  cat > "$RULES_CRON" <<EOF
# v2ray-rules-dat 每周三 04:15 自动更新 (由 install.sh 生成)
15 4 * * 3 root $INSTALL_DIR/install.sh update-rules >/dev/null 2>&1
EOF
  if [ -f "$RULES_CRON" ]; then
    chmod 0644 "$RULES_CRON" 2>/dev/null || true
    ok "已配置每周自动更新规则: $RULES_CRON"
  else
    warn "无法写入 $RULES_CRON (文件系统只读?), 可手动执行 update-rules"
  fi
}
