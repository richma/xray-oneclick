# 在 3x-ui/run.sh 的 PORTS=(...) 闭合括号前插入一行端口映射 (真正换行, 不用 sed \\n)
xui_insert_port_mapping() {
  local file="$1" port="$2"
  [ -f "$file" ] || return 1
  awk -v p="$port" '
    BEGIN { inports=0; done=0 }
    /^PORTS=\(/ { inports=1 }
    inports && /^\)/ && !done {
      print "  -p " p ":" p
      done=1
      inports=0
    }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

parse_xui_base_path() {
  local info="${1:-$INSTALL_DIR/3x-ui/info.txt}"
  local run="${2:-$INSTALL_DIR/3x-ui/run.sh}"
  local p=""
  if [ -f "$info" ]; then
    p="$(grep -oE ':[0-9]+/[^[:space:]]+' "$info" 2>/dev/null | head -1 | sed 's/^:[0-9]*//')"
  fi
  if [ -z "$p" ] && [ -f "$run" ]; then
    p="$(sed -n "s/^BASE_PATH='\\(.*\\)'/\\1/p" "$run" | head -1)"
  fi
  if [ -z "$p" ] && [ -n "${XUI_BASE_PATH:-}" ]; then
    p="$XUI_BASE_PATH"
  fi
  printf '%s' "$p"
}

install_3xui() {
  [ "${INSTALL_3XUI:-1}" = 0 ] && { info "已跳过 3X-UI 安装"; return 0; }
  if docker ps --format '{{.Names}}' | grep -qx "3x-ui"; then
    ok "3X-UI 容器已在运行, 跳过安装"
    return 0
  fi
  if docker ps -a --format '{{.Names}}' | grep -qx "3x-ui"; then
    warn "3X-UI 容器已存在但未运行, 尝试启动"
    if docker start 3x-ui >/dev/null 2>&1; then
      ok "已启动已有 3X-UI 容器"
      return 0
    fi
    warn "启动失败, 将按现有 run.sh 重建"
    local xuidir_exist="$INSTALL_DIR/3x-ui"
    if [ -f "$xuidir_exist/run.sh" ]; then
      bash "$xuidir_exist/run.sh" || die "3X-UI 重建失败, 请查看: docker logs 3x-ui"
      return 0
    fi
    docker rm -f 3x-ui >/dev/null 2>&1 || true
  fi
  local xuidir="$INSTALL_DIR/3x-ui"
  mkdir -p "$xuidir/db" "$xuidir/cert" "$xuidir/acme"

  local basepath="${XUI_BASE_PATH:-}"
  if [ -z "$basepath" ]; then
    basepath="/xui-$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c1-8)"
  fi

  local rules_vols=""
  if [ -f "$RULES_DIR/geoip.dat" ] && [ -f "$RULES_DIR/geosite.dat" ]; then
    rules_vols="  -v '$RULES_DIR/geoip.dat:/app/bin/geoip.dat:ro' \\\\\n  -v '$RULES_DIR/geosite.dat:/app/bin/geosite.dat:ro' \\\\"
  fi

  cat > "$xuidir/run.sh" <<EOF
#!/usr/bin/env bash
# 3X-UI 容器运行脚本 (由 install.sh 生成)
# 面板内新增入站后, 用以下命令开放端口: bash $INSTALL_DIR/install.sh xui-port <端口>
set -e
IMAGE='$XUI_IMAGE'
BASE_PATH='$basepath'
PORTS=(
  -p $XUI_PORT:2053
)
docker rm -f 3x-ui 2>/dev/null || true
docker run -d --name 3x-ui --restart=unless-stopped \\
  --cap-add NET_ADMIN --cap-add NET_RAW \\
  "\${PORTS[@]}" \\
  -e XUI_INIT_WEB_BASE_PATH="\$BASE_PATH" \\
  -e XRAY_VMESS_AEAD_FORCED=false \\
  -e XUI_ENABLE_FAIL2BAN=true \\
  -v '$xuidir/db:/etc/x-ui' \\
  -v '$xuidir/cert:/root/cert' \\
  -v '$xuidir/acme:/root/.acme.sh' \\
$(printf '%b' "$rules_vols")
  --tty \\
  "\$IMAGE"
EOF
  chmod +x "$xuidir/run.sh"

  info "拉取 3X-UI 镜像 $XUI_IMAGE (约 200MB, 请耐心等待) ..."
  ensure_image "$XUI_IMAGE"
  info "启动 3X-UI 容器 ..."
  bash "$xuidir/run.sh" || die "3X-UI 启动失败, 请查看: docker logs 3x-ui"

  cat > "$xuidir/info.txt" <<EOF
3X-UI 面板信息
  面板地址: http://<服务器IP>:$XUI_PORT$basepath
  默认账号: admin
  默认密码: admin
  (首次登录后请立即在 面板设置 中修改账号密码与访问路径!)

说明:
  * 面板内的 xray 入站端口需在宿主机放行:
      bash $INSTALL_DIR/install.sh xui-port <端口>
  * 订阅/二维码: 面板 -> 入站列表 -> 客户端 -> 订阅(链接/二维码)
  * 若面板 2053 端口被占用, 可设置 XUI_PORT 环境变量后重装
  * 前置 Reality 容器 (install.sh 管理的 443 节点) 与面板入站是两套节点, 互不影响
EOF
  cat "$xuidir/info.txt"
  warn "面板默认账号密码均为 admin, 请立刻修改"
  ok "3X-UI 面板安装完成"
}

xui_port() {
  local xuidir="$INSTALL_DIR/3x-ui"
  [ -f "$xuidir/run.sh" ] || die "3X-UI 未安装 ($xuidir/run.sh 不存在)"
  local port added=0
  for port in "$@"; do
    [[ "$port" =~ ^[0-9]+$ ]] || die "端口无效: $port"
    if grep -qE "^-p ${port}:2053$|^[[:space:]]*-p ${port}:" "$xuidir/run.sh"; then
      warn "端口 $port 已发布, 跳过"
      continue
    fi
    xui_insert_port_mapping "$xuidir/run.sh" "$port" || die "写入端口映射失败: $port"
    ok "已添加端口映射: $port -> $port"
    added=1
  done
  [ "$added" = 1 ] || { info "没有新的端口需要发布"; return 0; }
  info "重新创建 3X-UI 容器以应用端口映射 ..."
  bash "$xuidir/run.sh" || die "3X-UI 重建失败"
  ok "端口映射已生效: $(docker port 3x-ui 2>/dev/null | tr '\n' ' ')"
}
