install_docker() {
  [ "${INSTALL_DOCKER:-1}" = 0 ] && { info "已跳过 Docker 安装"; return 0; }
  if command -v docker >/dev/null 2>&1; then
    ok "Docker 已安装: $(docker --version 2>/dev/null)"
    return 0
  fi
  info "开始安装 Docker ..."
  case "$OS_ID" in
    alpine)
      apk add --no-cache docker >/dev/null 2>&1 || apk add docker
      rc-update add docker boot >/dev/null 2>&1 || true
      service docker start >/dev/null 2>&1 || true
      ;;
    *)
      info "下载官方安装脚本 get.docker.com ..."
      local script_args=""
      if [ "${USE_MIRROR:-0}" = 1 ]; then
        info "使用阿里云镜像安装 Docker"
        script_args="--mirror Aliyun"
      fi
      if ! curl -fsSL --connect-timeout 15 https://get.docker.com -o /tmp/get-docker.sh; then
        try_download /tmp/get-docker.sh \
          "https://mirrors.aliyun.com/docker-ce/scripts/install.sh" \
          "https://get.daocloud.io/docker" || die "Docker 安装脚本下载失败"
        script_args=""
      fi
      # shellcheck disable=SC2086
      sh /tmp/get-docker.sh $script_args || die "Docker 安装失败"
      ;;
  esac
  systemctl enable --now docker >/dev/null 2>&1 || true
  command -v docker >/dev/null 2>&1 || die "Docker 未安装成功"
  ok "Docker 安装完成: $(docker --version)"
}

# 合并写入 /etc/docker/daemon.json, 保留已有键 (bip/live-restore 等)
merge_docker_daemon_json() {
  local path="$1"
  shift
  local mirrors=("$@")
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" "${mirrors[@]}" <<'PY'
import json, sys, os
path = sys.argv[1]
mirrors = sys.argv[2:]
data = {}
if os.path.isfile(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
    except Exception:
        data = {}
existing = data.get("registry-mirrors") or []
if not isinstance(existing, list):
    existing = []
for m in mirrors:
    if m and m not in existing:
        existing.append(m)
data["registry-mirrors"] = existing
data.setdefault("log-driver", "json-file")
opts = data.get("log-opts")
if not isinstance(opts, dict):
    opts = {}
opts.setdefault("max-size", "100m")
opts.setdefault("max-file", "3")
data["log-opts"] = opts
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
    return $?
  fi
  if [ -f "$path" ]; then
    warn "未找到 python3, 且 $path 已存在, 跳过覆盖 (避免丢掉已有 Docker 配置)"
    return 1
  fi
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m", "max-file": "3" }
}
EOF
}

setup_docker_mirror() {
  [ "${USE_MIRROR:-0}" = 0 ] && return 0
  [ -f /etc/docker/daemon.json ] && cp -f /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null || true
  merge_docker_daemon_json /etc/docker/daemon.json \
    "https://docker.1ms.run" \
    "https://docker.m.daocloud.io" \
    "https://docker.1panel.live" \
    || return 0
  systemctl restart docker >/dev/null 2>&1 || service docker restart >/dev/null 2>&1 || true
  ok "已配置 Docker 国内镜像加速 (保留原 daemon.json 其它字段)"
}

ensure_image() {
  local img="$1" alt=""
  if docker image inspect "$img" >/dev/null 2>&1; then return 0; fi
  info "拉取镜像: $img (可能需要几分钟) ..."
  if docker pull "$img" >/dev/null 2>&1; then ok "镜像就绪: $img"; return 0; fi
  case "$img" in
    ghcr.io/*)
      alt="${img/ghcr.io/$GHCR_MIRROR}"
      if docker pull "$alt" >/dev/null 2>&1; then
        docker tag "$alt" "$img"; ok "镜像就绪: $img (经 $GHCR_MIRROR)"; return 0
      fi
      ;;
    *)
      local m
      for m in "${DOCKER_HUB_MIRRORS[@]}"; do
        if docker pull "$m/$img" >/dev/null 2>&1; then
          docker tag "$m/$img" "$img"; ok "镜像就绪: $img (经 $m)"; return 0
        fi
      done
      ;;
  esac
  die "镜像拉取失败: $img (网络受限时可加 -m/--mirror 使用国内镜像)"
}
