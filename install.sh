#!/usr/bin/env bash
# ==============================================================================
#  Xray Reality (Docker 前置) + 3X-UI 一键安装脚本
# ------------------------------------------------------------------------------
#  特性:
#    * BBR 拥塞控制 + 网络内核优化 (sysctl)
#    * Docker / Docker Compose 安装 (可选国内镜像加速)
#    * xray reality docker 镜像前置: wulabing/xray_docker_reality (官方镜像)
#    * 路由规则增强: v2ray-rules-dat (Loyalsoldier) geoip.dat / geosite.dat
#    * 协议伪装: SERVERNAMES_ZH.MD 伪装站点列表 + 可选域名 self-steal 模式
#    * 集成 3X-UI 后台: 多节点管理 / 订阅 / 二维码
#    * 多节点: 一条命令添加更多 Reality 节点
#    * 订阅: vless 链接 + 终端内 UTF8 二维码 + 3X-UI 订阅链接
#
#  参考项目:
#    * https://github.com/wulabing/xray_docker          (reality 镜像)
#    * https://github.com/XTLS/Xray-core
#    * https://github.com/MHSanaei/3x-ui
#    * https://github.com/Loyalsoldier/v2ray-rules-dat
#
#  用法:
#    bash install.sh                 # 交互式菜单
#    bash install.sh -y              # 全自动安装 (默认参数)
#    bash install.sh install -p 443 -n tcp -d your.domain.com
#    bash install.sh add-node -p 8443
#    bash install.sh update-rules    # 更新 v2ray-rules-dat
#    bash install.sh info            # 查看节点信息/订阅/二维码
#    bash install.sh xui-port 8388   # 为 3X-UI 开放新端口
#    bash install.sh uninstall
# ==============================================================================

# ---------------------------- 基础配置 ---------------------------------------
VERSION="1.0.0"
INSTALL_DIR="${INSTALL_DIR:-/opt/xray-oneclick}"
REALITY_IMAGE="${REALITY_IMAGE:-wulabing/xray_docker_reality:latest}"
XUI_IMAGE="${XUI_IMAGE:-ghcr.io/mhsanaei/3x-ui:latest}"
XUI_PORT="${XUI_PORT:-2053}"
RULES_DIR="$INSTALL_DIR/rules"
NODES_FILE="$INSTALL_DIR/nodes.ini"
SUB_FILE="$INSTALL_DIR/subscription.txt"
TEMPLATE_JSON="$INSTALL_DIR/conf/xray-config.template.json"
SYSCTL_CONF="$INSTALL_DIR/conf/sysctl-xray.conf"
SYSCTL_FILE="/etc/sysctl.d/99-xray-optimize.conf"
RULES_CRON="/etc/cron.d/xray-rules-update"
SERVERNAMES_FILE="$INSTALL_DIR/conf/SERVERNAMES_ZH.MD"
MIN_CLIENT_VER="${MIN_CLIENT_VER:-}"
SHORTIDS="${SHORTIDS:-}"
PANEL_PROXY_PORT="${PANEL_PROXY_PORT:-9443}"
PANEL_PROXY_PASS="${PANEL_PROXY_PASS:-}"
SUB_SERVER_PORT="${SUB_SERVER_PORT:-8080}"

# 国内镜像 (--mirror 时启用)
DOCKER_HUB_MIRRORS=(
  "docker.1ms.run"
  "docker.m.daocloud.io"
  "docker.1panel.live"
  "hub.rat.dev"
)
GHCR_MIRROR="${GHCR_MIRROR:-ghcr.nju.edu.cn}"
GITHUB_RAW_MIRRORS=(
  "https://ghfast.top/"
  "https://gh-proxy.com/"
  "https://ghproxy.net/"
  "https://raw.gitmirror.com/"
)

ASSUME_YES=0
USE_MIRROR=0
INSTALL_3XUI=1
ENABLE_BBR=1
INSTALL_DOCKER=1
INSTALL_RULES=1

# 参数 (install)
REALITY_PORT=""
NETWORK_MODE=""
DEST_ARG=""
SERVERNAMES_ARG=""
DOMAIN_ARG=""
ACME_EMAIL_ARG=""
PROXY_ARG=""
UUID_ARG=""

# ---------------------------- 输出函数 ---------------------------------------
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'; C_BOLD='\033[1m'

info()  { printf "${C_CYAN}[信息]${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}[成功]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[警告]${C_RESET} %s\n" "$*"; }
die()   { printf "${C_RED}[错误]${C_RESET} %s\n" "$*"; exit 1; }
banner(){ printf "${C_BOLD}%s${C_RESET}\n" "$*"; }

# ---------------------------- 辅助函数 ---------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

usage() {
  cat <<EOF
Xray Reality + 3X-UI 一键安装脚本 v${VERSION}

用法: bash install.sh [子命令] [选项]

子命令:
  install       执行安装 (默认)
  add-node      添加更多 Reality 节点 (多节点)
  update-rules  更新 v2ray-rules-dat 规则文件并重启节点
  info          查看节点信息 / 订阅 / 二维码
  xui-port <p>  为 3X-UI 面板开放新端口 (面板内新增入站后使用)
  panel-proxy   面板 HTTPS 反向代理 (Caddy 自动签发证书): -d <域名> [--panel-port <端口>] [--panel-pass <密码>]
  sub-server    节点订阅 HTTP 服务 (供主面板"外部订阅"聚合本节点): [--sub-port <端口>]
  uninstall     卸载全部组件

选项:
  -y, --yes            全自动安装, 使用默认值不询问
  -p, --port <端口>    Reality 对外端口 (默认 443)
  -n, --network <模式> Reality 网络模式: tcp(vision) 或 xhttp (默认 tcp)
  -d, --domain <域名>  域名 self-steal 模式 (需 DNS 已指向本机, 自动签发证书)
  -e, --email <邮箱>   ACME 证书邮箱 (配合 -d)
  -u, --uuid <UUID>    自定义 UUID (默认自动生成)
  -P, --proxy <URL>    后置代理 socks5:// 或 http:// (家宽IP解锁场景)
  --panel-port <端口>  面板 HTTPS 反代端口 (默认 9443, 配合 panel-proxy)
  --panel-pass <密码>  面板 HTTPS 反代登录密码 (可选, 配合 panel-proxy)
  --sub-port <端口>    节点订阅 HTTP 服务端口 (默认 8080, 配合 sub-server)
  -x, --no-3xui        不安装 3X-UI 面板
  -b, --no-bbr         跳过 BBR 与内核优化
  -c, --no-docker      跳过 Docker 安装 (已安装时)
  -r, --no-rules       跳过 v2ray-rules-dat 下载
  -m, --mirror         使用国内镜像加速 (docker/ghcr/github)
  -h, --help           显示帮助

示例:
  bash install.sh -y                                    # 一键默认安装
  bash install.sh -p 8443 -n xhttp -x                   # 仅 Reality, 8443 端口 xhttp
  bash install.sh -d vpn.example.com -e a@b.com         # 域名 self-steal
  bash install.sh add-node -p 8443 -y                   # 添加第二个节点
  bash install.sh panel-proxy -d panel.example.com      # 面板 HTTPS 反代 (Caddy)
  bash install.sh sub-server                            # 节点订阅 HTTP 服务 (供聚合)
EOF
}

ask() {  # ask "提示" "默认值" -> $ANSWER
  local prompt="$1" def="$2"
  if [ "$ASSUME_YES" = 1 ]; then ANSWER="$def"; return; fi
  printf "%s [%s]: " "$prompt" "$def"; read -r ans
  ANSWER="${ans:-$def}"
}

ask_yn() {  # ask_yn "提示" "默认(y/n)" -> $ANSWER (y/n)
  local prompt="$1" def="$2" ans
  if [ "$ASSUME_YES" = 1 ]; then ANSWER="$def"; return; fi
  printf "%s (y/n) [%s]: " "$prompt" "$def"; read -r ans
  case "${ans:-$def}" in y|Y|yes|YES) ANSWER=y ;; *) ANSWER=n ;; esac
}

confirm() {  # confirm "问题" -> 0/1
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi
  printf "${C_YELLOW}%s (y/n): ${C_RESET}" "$1"; read -r a
  case "$a" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

try_download() {  # try_download <out> <url...> ; 依次尝试多个 URL
  local out="$1"; shift
  local u
  for u in "$@"; do
    if curl -fsSL --connect-timeout 10 --max-time 120 -o "$out" "$u" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# 生成 GitHub raw 的镜像 URL 列表
raw_urls() {  # raw_urls <github_raw_url> -> 输出候选 URL (含镜像)
  local url="$1" path="${1#https://raw.githubusercontent.com/}"
  echo "$url"
  for m in "${GITHUB_RAW_MIRRORS[@]}"; do
    case "$m" in
      *gitmirror*|*raw.gitmirror*) echo "${m}${path}" ;;
      *) echo "${m}${url}" ;;
    esac
  done
}

# ---------------------------- 环境检测 ---------------------------------------
check_root() {
  [ "$(id -u)" = 0 ] || die "请以 root 权限运行: sudo bash install.sh"
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"; OS_NAME="$NAME"; OS_VERSION="$VERSION_ID"
  else
    OS_ID="unknown"; OS_NAME="unknown"; OS_VERSION="unknown"
  fi
  case "$OS_ID" in
    debian|ubuntu|centos|rocky|almalinux|fedora|rhel|alpine) ;;
    *) die "暂不支持的系统: $OS_NAME ($OS_ID), 请使用 Debian/Ubuntu/CentOS/Rocky/AlmaLinux/Fedora/Alpine" ;;
  esac
  info "系统: $OS_NAME $OS_VERSION"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l|armv6l|armv5tel) ARCH="arm" ;;
    *) die "不支持的 CPU 架构: $(uname -m)" ;;
  esac
}

detect_virt() {
  VIRT=""
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT="$(systemd-detect-virt 2>/dev/null || true)"
  fi
  if [ -d /proc/vz ] || [ -f /proc/user_beancounters ]; then
    VIRT="openvz"
  fi
  case "$VIRT" in
    openvz|lxc) warn "检测到虚拟化: $VIRT, BBR 可能无法启用 (可跳过 -b)" ;;
    "") : ;;
    *) info "虚拟化环境: $VIRT" ;;
  esac
}

check_network() {
  curl -fsSL --connect-timeout 5 -o /dev/null https://www.google.com 2>/dev/null \
    || warn "无法访问 google.com (网络受限?), 安装过程将尽量使用镜像"
}

# ---------------------------- BBR / 内核优化 ---------------------------------
apply_sysctl() {
  [ "$ENABLE_BBR" = 0 ] && { info "已跳过 BBR 与内核优化"; return 0; }
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

  # 写入系统目录
  if ! cp -f "$SYSCTL_CONF" "$SYSCTL_FILE" 2>/dev/null; then
    warn "无法写入 $SYSCTL_FILE (无权限?), 内核优化未应用"
    return 1
  fi
  sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || warn "部分 sysctl 参数未生效 (内核不支持时属正常)"
  ok "内核参数优化已应用 ($SYSCTL_FILE)"
}

enable_bbr() {
  [ "$ENABLE_BBR" = 0 ] && return 0
  if [ ! -w "$SYSCTL_FILE" ]; then
    warn "无法写入 $SYSCTL_FILE, 跳过 BBR 配置"
    return 1
  fi
  if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
    ok "BBR 已启用 (tcp_congestion_control=bbr)"
    return 0
  fi
  # 尝试加载模块
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
    # fq 不可用时回退 fq_codel
    sed -i 's/^net.core.default_qdisc = fq$/net.core.default_qdisc = fq_codel/' "$SYSCTL_FILE" 2>/dev/null
    sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true
    if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
      ok "BBR 已启用 (fq 不可用, 回退 fq_codel)"
    else
      warn "BBR 启用失败, 当前拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    fi
  fi
}

# ---------------------------- Docker 安装 ------------------------------------
install_docker() {
  [ "$INSTALL_DOCKER" = 0 ] && { info "已跳过 Docker 安装"; return 0; }
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
      if [ "$USE_MIRROR" = 1 ]; then
        info "使用阿里云镜像安装 Docker"
        script_args="--mirror Aliyun"
      fi
      if ! curl -fsSL --connect-timeout 15 https://get.docker.com -o /tmp/get-docker.sh; then
        # 镜像源兜底
        try_download /tmp/get-docker.sh \
          "https://mirrors.aliyun.com/docker-ce/scripts/install.sh" \
          "https://get.daocloud.io/docker" || die "Docker 安装脚本下载失败"
        script_args=""
      fi
      sh /tmp/get-docker.sh $script_args || die "Docker 安装失败"
      ;;
  esac
  systemctl enable --now docker >/dev/null 2>&1 || true
  command -v docker >/dev/null 2>&1 || die "Docker 未安装成功"
  ok "Docker 安装完成: $(docker --version)"
}

setup_docker_mirror() {
  [ "$USE_MIRROR" = 0 ] && return 0
  [ -f /etc/docker/daemon.json ] && cp -f /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null || true
  cat > /etc/docker/daemon.json <<EOF
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
  systemctl restart docker >/dev/null 2>&1 || service docker restart >/dev/null 2>&1 || true
  ok "已配置 Docker 国内镜像加速"
}

ensure_image() {  # ensure_image <image>
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
      for m in "${DOCKER_HUB_MIRRORS[@]}"; do
        if docker pull "$m/$img" >/dev/null 2>&1; then
          docker tag "$m/$img" "$img"; ok "镜像就绪: $img (经 $m)"; return 0
        fi
      done
      ;;
  esac
  die "镜像拉取失败: $img (网络受限时可加 -m/--mirror 使用国内镜像)"
}

# ---------------------------- v2ray-rules-dat --------------------------------
download_rules() {
  [ "$INSTALL_RULES" = 0 ] && { warn "已跳过 v2ray-rules-dat 下载"; return 0; }
  mkdir -p "$RULES_DIR"
  local base="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
  local js="https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release"
  local f url ok_all=1
  info "下载 v2ray-rules-dat 规则文件 (geoip.dat / geosite.dat) ..."
  for f in geoip.dat geosite.dat; do
    if [ -s "$RULES_DIR/$f" ] && [ "$FORCE_RULES" = 1 ]; then rm -f "$RULES_DIR/$f"; fi
    if [ -s "$RULES_DIR/$f" ] && [ -s "$RULES_DIR/$f.sha256sum" ] \
       && (cd "$RULES_DIR" && sha256sum -c "$f.sha256sum" --status 2>/dev/null); then
      ok "规则文件已存在且校验通过: $f"
      continue
    fi
    url=""
    if try_download "$RULES_DIR/$f" "$base/$f" "$js/$f"; then
      try_download "$RULES_DIR/$f.sha256sum" "$base/$f.sha256sum" "$js/$f.sha256sum" || true
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

# ---------------------------- 伪装站点 (SERVERNAMES_ZH.MD) --------------------
fetch_servernames() {
  mkdir -p "$INSTALL_DIR/conf"
  if [ ! -s "$SERVERNAMES_FILE" ]; then
    info "获取伪装站点列表 SERVERNAMES_ZH.MD ..."
    try_download "$SERVERNAMES_FILE" \
      $(raw_urls "https://raw.githubusercontent.com/wulabing/xray_docker/master/reality/SERVERNAMES_ZH.MD") \
      "https://cdn.jsdelivr.net/gh/wulabing/xray_docker@master/reality/SERVERNAMES_ZH.MD" || {
      warn "SERVERNAMES_ZH.MD 获取失败, 使用内置默认值 (www.apple.com)"
    }
  fi
}

# 解析 md 表格: 输出 "DEST<TAB>SERVERNAMES" 每行
parse_servernames() {
  [ -s "$SERVERNAMES_FILE" ] || return 0
  awk -F'|' '
    /^\|/ {
      d=$2; s=$3
      gsub(/^ +| +$/, "", d); gsub(/^ +| +$/, "", s)
      if (d ~ /^[^ |]+\.[^ |]+:[0-9]+$/ && s != "" && d != "DEST") {
        print d "\t" s
      }
    }' "$SERVERNAMES_FILE"
}

pick_dest() {  # 交互选择伪装站点 -> $DEST/$SERVERNAMES
  local choice=0 n=0 line d s
  fetch_servernames
  local list=()
  while IFS=$'\t' read -r d s; do
    [ -n "$d" ] && list+=("$d|$s")
  done < <(parse_servernames)
  if [ "${#list[@]}" = 0 ]; then
    DEST="www.apple.com:443"; SERVERNAMES="images.apple.com www.apple.com"
    return 0
  fi
  banner "可用的伪装站点 (Reality DEST / SERVERNAMES):"
  for i in "${!list[@]}"; do
    d="${list[$i]%|*}"; s="${list[$i]#*|}"
    printf "  ${C_CYAN}%d${C_RESET}) %-28s SNI: %s\n" "$((i+1))" "$d" "$s"
  done
  ask "选择伪装站点" "1"
  choice="$ANSWER"
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#list[@]}" ]; then
    warn "输入无效, 使用默认第 1 项"; choice=1
  fi
  DEST="${list[$((choice-1))]%|*}"
  SERVERNAMES="${list[$((choice-1))]#*|}"
  ok "伪装站点: DEST=$DEST  SERVERNAMES=$SERVERNAMES"
}

# ---------------------------- 节点注册表 -------------------------------------
save_node() {  # save_node <port> <container> <network> <data_dir> <domain>
  local port="$1" container="$2" network="$3" data_dir="$4" domain="${5:-}"
  touch "$NODES_FILE"
  grep -v "^${port}|" "$NODES_FILE" > "$NODES_FILE.tmp" 2>/dev/null || true
  echo "${port}|${container}|${network}|${data_dir}|${domain}" >> "$NODES_FILE.tmp"
  mv "$NODES_FILE.tmp" "$NODES_FILE"
}

remove_node() {  # remove_node <port>
  grep -v "^${1}|" "$NODES_FILE" > "$NODES_FILE.tmp" 2>/dev/null || true
  mv "$NODES_FILE.tmp" "$NODES_FILE"
}

node_containers() {  # 输出所有节点容器名
  awk -F'|' '!/^#/ && NF>=2 {print $2}' "$NODES_FILE" 2>/dev/null
}

# ---------------------------- Reality 节点 ------------------------------------
gen_uuid() {
  local u
  u="$(cat /proc/sys/kernel/random/uuid 2>/dev/null)"
  [ -z "$u" ] && u="$(docker run --rm --entrypoint /xray "$REALITY_IMAGE" uuid 2>/dev/null)"
  [ -z "$u" ] && u="$(date +%s%N)-$(hostname)-$$"
  echo "$u"
}

container_name_for() {  # container_name_for <port>
  [ "$1" = "443" ] && echo "xray_reality" || echo "xray_reality_$1"
}

check_port_free() {
  local port="$1" name
  command -v ss >/dev/null 2>&1 || return 0
  name="$(container_name_for "$port")"
  # 端口被我们自己的节点容器占用时允许重建 (重装/换域名场景)
  if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    return 0
  fi
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
    die "端口 $port 已被占用, 请更换端口 (-p <端口>)"
  fi
}

run_reality_container() {  # run_reality_container <port> <network> [dest] [servernames] [domain] [email] [proxy] [uuid]
  local port="$1" network="$2" dest="${3:-www.apple.com:443}" sn="${4:-images.apple.com www.apple.com}"
  local domain="${5:-}" email="${6:-}" proxy="${7:-}" uuid_opt="${8:-}"
  local name node_dir
  name="$(container_name_for "$port")"
  node_dir="$INSTALL_DIR/nodes/node_$port"
  mkdir -p "$node_dir/data"

  ensure_base_files
  [ -f "$TEMPLATE_JSON" ] || die "配置文件模板缺失: $TEMPLATE_JSON"

  # 生成 wrapper entrypoint: 将增强路由配置模板注入容器可写层,
  # 再执行镜像原始入口 (避免 bind-mount /config.json 导致 entrypoint 的 mv 失败)
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
  )
  [ -n "$uuid_opt" ] && args+=(-e UUID="$uuid_opt")
  [ -n "$SHORTIDS" ] && args+=(-e SHORTIDS="$SHORTIDS")
  [ -n "$MIN_CLIENT_VER" ] && args+=(-e MIN_CLIENT_VER="$MIN_CLIENT_VER")
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
  # v2ray-rules-dat: 文件存在才挂载, 否则使用镜像内自带规则
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

  # 可选: 注入自定义 Caddyfile (如面板 HTTPS 反向代理站点)
  if [ -n "${NODE_CADDYFILE:-}" ] && [ -f "$NODE_CADDYFILE" ]; then
    info "挂载自定义 Caddyfile: $NODE_CADDYFILE"
    args+=(-v "$NODE_CADDYFILE:/etc/caddy/Caddyfile:ro")
  fi
  # 可选: 额外发布的端口 (格式 "外:内 外:内")
  if [ -n "${NODE_EXTRA_PORTS:-}" ]; then
    local pp
    for pp in $NODE_EXTRA_PORTS; do
      info "额外发布端口: $pp"
      args+=(-p "$pp")
    done
  fi

  args+=("$REALITY_IMAGE")

  docker rm -f "$name" >/dev/null 2>&1 || true
  info "启动 Reality 节点容器: $name (端口 $port / $network) ..."
  docker run "${args[@]}" || die "容器启动失败, 请查看: docker logs $name"

  wait_node_ready "$name" "$node_dir/data/reality_config_info.txt"
  save_node "$port" "$name" "$network" "$node_dir" "$domain"
  update_subscription
  show_node_card "$node_dir"
}

wait_node_ready() {  # wait_node_ready <container> <info_file>
  local name="$1" info_file="$2" i
  for i in $(seq 1 60); do
    if [ -s "$info_file" ]; then return 0; fi
    if ! docker ps --filter "name=^/${name}$" --format '{{.Names}}' | grep -qx "$name"; then
      die "容器 $name 已退出, 请查看日志: docker logs $name"
    fi
    sleep 2
  done
  warn "等待 $name 生成配置超时, 可稍后执行: bash install.sh info"
}

# 从节点 info 文件读取字段
node_field() {  # node_field <info_file> <field>
  local info_file="$1" field="$2"
  case "$field" in
    uuid)      sed -n 's/^UUID: //p' "$info_file" | head -1 ;;
    dest)      sed -n 's/^DEST: //p' "$info_file" | head -1 ;;
    port)      sed -n 's/^PORT: //p' "$info_file" | head -1 ;;
    servernames) sed -n 's/^SERVERNAMES: //p' "$info_file" | head -1 | sed 's/ (.*$//' ;;
    pub)       sed -n 's/^PUBLICKEY\/PASSWORD: //p' "$info_file" | head -1 ;;
    net)       sed -n 's/^NETWORK: //p' "$info_file" | head -1 ;;
    shortid)   sed -n 's/^SHORTID: //p' "$info_file" | head -1 | awk '{print $1}' ;;
    xhttp_path) sed -n 's/^XHTTP_PATH: //p' "$info_file" | head -1 ;;
    *) echo "" ;;
  esac
}

build_vless_link() {  # build_vless_link <node_dir> <ip> ; 镜像内 IP 检测失败时的兜底
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
  [ -z "$ext" ] && ext="$REALITY_PORT"
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
    # 优先取容器内生成的 vless 链接
    if grep -q "vless://" "$info_file"; then
      grep -o 'vless://[^#]*' "$info_file" | sort -u >> "$SUB_FILE"
    else
      # 兜底: 用宿主机 IP 重建
      ip="$(curl -4 -sSL --connect-timeout 5 --retry 1 ip.sb 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
      [ -z "$ip" ] && ip="YOUR_SERVER_IP"
      link="$(build_vless_link "$data_dir" "$ip")" && echo "$link" >> "$SUB_FILE"
    fi
  done < "$NODES_FILE"
  [ -s "$SUB_FILE" ] && ok "订阅链接已汇总: $SUB_FILE"
}

show_node_card() {  # show_node_card <node_dir>
  local node_dir="$1" info_file="$node_dir/data/reality_config_info.txt"
  if [ -s "$info_file" ]; then
    banner "══════════ 节点配置信息 (含二维码) ══════════"
    cat "$info_file"
    banner "════════════════════════════════════════════"
  fi
}

# ---------------------------- 3X-UI ------------------------------------------
install_3xui() {
  [ "$INSTALL_3XUI" = 0 ] && { info "已跳过 3X-UI 安装"; return 0; }
  if docker ps -a --format '{{.Names}}' | grep -qx "3x-ui"; then
    ok "3X-UI 容器已存在, 跳过安装 (重新创建: bash install.sh uninstall 后重装)"
    return 0
  fi
  local xuidir="$INSTALL_DIR/3x-ui"
  mkdir -p "$xuidir/db" "$xuidir/cert" "$xuidir/acme"

  local basepath="${XUI_BASE_PATH:-}"
  if [ -z "$basepath" ]; then
    basepath="/xui-$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c1-8)"
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
  --tty \\
  "\$IMAGE"
EOF
  # v2ray-rules-dat: 规则文件存在时挂载进 3X-UI (面板节点同样使用 Loyalsoldier 规则)
  if [ -f "$RULES_DIR/geoip.dat" ] && [ -f "$RULES_DIR/geosite.dat" ]; then
    sed -i "/acme:\/root\/.acme.sh/a\  -v '$RULES_DIR/geoip.dat:/app/bin/geoip.dat:ro' \\\\\n  -v '$RULES_DIR/geosite.dat:/app/bin/geosite.dat:ro' \\\\" "$xuidir/run.sh"
  fi
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
EOF
  cat "$xuidir/info.txt"
  ok "3X-UI 面板安装完成"
}

xui_port() {  # xui_port <port...>
  local xuidir="$INSTALL_DIR/3x-ui"
  [ -f "$xuidir/run.sh" ] || die "3X-UI 未安装 ($xuidir/run.sh 不存在)"
  local port
  for port in "$@"; do
    [[ "$port" =~ ^[0-9]+$ ]] || die "端口无效: $port"
    if grep -q "^-p $port:2053\|^  -p $port:" "$xuidir/run.sh"; then
      warn "端口 $port 已发布, 跳过"
      continue
    fi
    # 在 PORTS=( ... ) 数组的闭合括号前插入
    sed -i "s/^)/  -p $port:$port\\n)/" "$xuidir/run.sh"
    ok "已添加端口映射: $port -> $port"
  done
  info "重新创建 3X-UI 容器以应用端口映射 ..."
  bash "$xuidir/run.sh" || die "3X-UI 重建失败"
  ok "端口映射已生效: $(docker port 3x-ui 2>/dev/null | tr '\n' ' ')"
}

# ---------------------------- 防火墙 ------------------------------------------
open_firewall() {  # open_firewall <port...>
  local ports=("$@")
  [ "${#ports[@]}" = 0 ] && return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    for p in "${ports[@]}"; do
      ufw allow "${p}/tcp" >/dev/null 2>&1
      ufw allow "${p}/udp" >/dev/null 2>&1
    done
    ok "ufw 已放行端口: ${ports[*]}"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1
      firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1
    done
    firewall-cmd --reload >/dev/null 2>&1
    ok "firewalld 已放行端口: ${ports[*]}"
  elif command -v iptables >/dev/null 2>&1 && iptables -L -n >/dev/null 2>&1 \
       && iptables -L INPUT -n 2>/dev/null | grep -q "policy DROP\|DROP"; then
    for p in "${ports[@]}"; do
      iptables -I INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1
      iptables -I INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1
    done
    ok "iptables 已放行端口: ${ports[*]}"
  else
    info "未检测到活动防火墙, 跳过 (若使用云安全组请自行放行: ${ports[*]})"
  fi
}

# ---------------------------- 定时更新规则 ------------------------------------
install_cron() {
  [ "$INSTALL_RULES" = 0 ] && return 0
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

# ---------------------------- 基础目录/模板 -----------------------------------
ensure_base_files() {
  mkdir -p "$INSTALL_DIR/conf" "$INSTALL_DIR/rules" "$INSTALL_DIR/nodes" \
           "$INSTALL_DIR/3x-ui/db" "$INSTALL_DIR/3x-ui/cert" "$INSTALL_DIR/3x-ui/acme"

  # 自副本: 供定时任务 / 子命令 / 后续管理使用
  if [ -f "$SCRIPT_DIR/install.sh" ] && [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp -f "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/install.sh" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/install.sh" 2>/dev/null || true
  fi

  # 配置模板: 优先使用脚本同目录 conf/, 否则内嵌
  if [ ! -f "$TEMPLATE_JSON" ]; then
    if [ -f "$SCRIPT_DIR/conf/xray-config.template.json" ]; then
      cp -f "$SCRIPT_DIR/conf/xray-config.template.json" "$TEMPLATE_JSON"
    else
      cat > "$TEMPLATE_JSON" <<'TEMPLATE_JSON_EMBEDDED'
{
  "log": {
    "loglevel": "error",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "api": {
    "tag": "api",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "dns": {
    "servers": [
      "https+local://cloudflare-dns.com/dns-query",
      "https+local://dns.google/dns-query",
      "1.1.1.1",
      "8.8.8.8",
      "1.0.0.1",
      "localhost"
    ]
  },
  "inbounds": [
    {
      "tag": "dokodemo-in",
      "port": 443,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 65432,
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "tls"
        ],
        "routeOnly": true
      }
    },
    {
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "port": 65432,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "xx",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": true,
          "target": "xx",
          "xver": 0,
          "maxTimeDiff": 0,
          "minClientVer": "1.0.0",
          "serverNames": [
            "xx"
          ],
          "privateKey": "xx",
          "shortIds": [
            ""
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "domain": [
          "xx"
        ],
        "outboundTag": "direct"
      },
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "outboundTag": "blocked"
      },
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "domain": [
          "geosite:category-ads-all"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": [
          "geosite:private"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": [
          "geosite:cn"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "geoip:cn"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
TEMPLATE_JSON_EMBEDDED
    fi
  fi

  if [ ! -f "$SYSCTL_CONF" ]; then
    if [ -f "$SCRIPT_DIR/conf/sysctl-xray.conf" ]; then
      cp -f "$SCRIPT_DIR/conf/sysctl-xray.conf" "$SYSCTL_CONF"
    fi
  fi
}

# ---------------------------- 安装流程 ----------------------------------------
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

  # 1. BBR + 内核优化
  if [ "$ENABLE_BBR" = 1 ]; then
    ask_yn "是否启用 BBR + 内核网络优化?" "y"
    [ "$ANSWER" = "n" ] && ENABLE_BBR=0
  fi
  apply_sysctl
  enable_bbr

  # 2. Docker
  if [ "$INSTALL_DOCKER" = 1 ] && ! command -v docker >/dev/null 2>&1; then
    ask_yn "是否安装 Docker?" "y"
    [ "$ANSWER" = "n" ] && INSTALL_DOCKER=0
  fi
  install_docker
  setup_docker_mirror
  command -v docker >/dev/null 2>&1 || die "Docker 不可用, 无法继续"

  # 3. 伪装站点选择
  if [ -z "$DEST_ARG" ] && [ -z "$DOMAIN_ARG" ]; then
    pick_dest
  else
    DEST="${DEST_ARG:-www.apple.com:443}"
    SERVERNAMES="${SERVERNAMES_ARG:-images.apple.com www.apple.com}"
  fi

  # 4. Reality 参数
  if [ -z "$REALITY_PORT" ]; then
    ask "Reality 对外端口" "443"
    REALITY_PORT="$ANSWER"
  fi
  if [ -z "$NETWORK_MODE" ]; then
    ask "网络模式 (tcp=vision / xhttp)" "tcp"
    case "$ANSWER" in
      xhttp) NETWORK_MODE="xhttp" ;;
      *) NETWORK_MODE="tcp" ;;
    esac
  fi
  if [ -z "$DOMAIN_ARG" ]; then
    ask_yn "配置域名 self-steal 伪装 (需要域名已解析到本机)?" "n"
    [ "$ANSWER" = "y" ] && {
      ask "请输入域名" ""; DOMAIN_ARG="$ANSWER"
      ask "ACME 邮箱 (可留空)" ""; ACME_EMAIL_ARG="$ANSWER"
    }
  fi
  if [ -z "$UUID_ARG" ]; then
    # 复用已有节点的 UUID (重装/换域名时保持客户端配置不变)
    local existing_info="$INSTALL_DIR/nodes/node_${REALITY_PORT}/data/reality_config_info.txt"
    if [ -f "$existing_info" ]; then
      UUID_ARG="$(node_field "$existing_info" uuid)"
    fi
  fi
  if [ -z "$UUID_ARG" ]; then
    UUID_ARG="$(gen_uuid)"
    info "已生成 UUID: $UUID_ARG"
  fi

  check_port_free "$REALITY_PORT"
  [ -n "$DOMAIN_ARG" ] && check_port_free 80

  # 5. 3X-UI
  if [ "$INSTALL_3XUI" = 1 ]; then
    ask_yn "是否安装 3X-UI 管理面板 (订阅/二维码/多节点)?" "y"
    [ "$ANSWER" = "n" ] && INSTALL_3XUI=0
  fi

  # 6. 规则文件
  if [ "$INSTALL_RULES" = 1 ]; then
    ask_yn "是否下载 v2ray-rules-dat 加强版路由规则?" "y"
    [ "$ANSWER" = "n" ] && INSTALL_RULES=0
  fi

  if [ "$ASSUME_YES" != 1 ]; then
    confirm "确认开始安装?" || { info "已取消"; exit 0; }
  fi

  download_rules
  run_reality_container "$REALITY_PORT" "$NETWORK_MODE" "$DEST" "$SERVERNAMES" \
    "$DOMAIN_ARG" "$ACME_EMAIL_ARG" "$PROXY_ARG" "$UUID_ARG"
  install_3xui
  install_cron

  local fw_ports=("$REALITY_PORT")
  [ -n "$DOMAIN_ARG" ] && fw_ports+=(80)
  [ "$INSTALL_3XUI" = 1 ] && fw_ports+=("$XUI_PORT")
  open_firewall "${fw_ports[@]}"

  banner ""
  banner "══════════════════════════════ 安装完成 ══════════════════════════════"
  ok "Reality 节点已启动: 端口 $REALITY_PORT / $NETWORK_MODE"
  ok "路由规则: v2ray-rules-dat (Loyalsoldier) + 广告/直连/CN 分流规则"
  [ "$INSTALL_3XUI" = 1 ] && ok "3X-UI 面板: http://<服务器IP>:$XUI_PORT (信息见 $INSTALL_DIR/3x-ui/info.txt)"
  info "查看节点配置/二维码:  bash install.sh info"
  info "订阅链接汇总:         cat $SUB_FILE"
  info "添加更多节点:         bash install.sh add-node"
  banner "══════════════════════════════════════════════════════════════════════"
}

# ---------------------------- 子命令 -----------------------------------------
cmd_add_node() {
  check_root
  command -v docker >/dev/null 2>&1 || die "请先执行 install 安装基础环境"
  ensure_base_files
  [ -s "$RULES_DIR/geoip.dat" ] || download_rules

  local port network dest sn domain
  if [ -z "$REALITY_PORT" ]; then
    # 默认取第一个可用端口 (从 8443 起)
    local p=8443
    while grep -q "^${p}|" "$NODES_FILE" 2>/dev/null; do p=$((p+1)); done
    ask "新节点端口" "$p"
    REALITY_PORT="$ANSWER"
  fi
  port="$REALITY_PORT"
  check_port_free "$port"

  # 继承第一个节点的伪装/网络配置
  local first_line
  first_line="$(grep -v '^#' "$NODES_FILE" 2>/dev/null | head -1)"
  if [ -n "$first_line" ]; then
    local first_dir; first_dir="$(echo "$first_line" | awk -F'|' '{print $4}')"
    NETWORK_MODE="${NETWORK_MODE:-$(node_field "$first_dir/data/reality_config_info.txt" net)}"
  fi
  NETWORK_MODE="${NETWORK_MODE:-tcp}"
  if [ -z "$NETWORK_MODE" ]; then NETWORK_MODE="tcp"; fi

  if [ -z "$DEST_ARG" ] && [ -z "$DOMAIN_ARG" ]; then
    pick_dest
  else
    DEST="${DEST_ARG:-www.apple.com:443}"
    SERVERNAMES="${SERVERNAMES_ARG:-images.apple.com www.apple.com}"
  fi
  [ -z "$UUID_ARG" ] && UUID_ARG="$(gen_uuid)"

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
  ok "v2ray-rules-dat 更新完成"
}

cmd_info() {
  local port container network data_dir domain c
  local has=0
  while IFS='|' read -r port container network data_dir domain; do
    [ -n "$port" ] || continue
    has=1
    banner ""
    banner "────────────── 节点 $port (容器: $container) ──────────────"
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
    [ -f "$SUB_FILE" ] && cat "$SUB_FILE" || info "(暂无, 可执行 update-subscription)"
  else
    info "尚未安装任何节点, 请先执行: bash install.sh install"
  fi
  if docker ps -a --format '{{.Names}}' | grep -qx "3x-ui"; then
    banner ""
    banner "────────────── 3X-UI 面板 ──────────────"
    cat "$INSTALL_DIR/3x-ui/info.txt" 2>/dev/null
  fi
}

cmd_uninstall() {
  check_root
  banner "即将卸载以下组件:"
  for c in $(node_containers); do echo "  - 节点容器: $c"; done
  docker ps -a --format '{{.Names}}' | grep -qx "3x-ui" && echo "  - 3X-UI 容器"
  echo "  - 定时更新任务 $RULES_CRON"
  echo "  - 内核优化 $SYSCTL_FILE"
  confirm "确定卸载?" || { info "已取消"; exit 0; }

  local c
  for c in $(node_containers); do docker rm -f "$c" >/dev/null 2>&1 || true; done
  docker rm -f 3x-ui >/dev/null 2>&1 || true
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
    case "$OS_ID" in
      debian|ubuntu) apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1 || true ;;
      centos|rocky|almalinux|fedora|rhel) yum remove -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 || true ;;
      alpine) apk del docker >/dev/null 2>&1 || true ;;
    esac
    ok "Docker 已卸载"
  fi
  ok "卸载完成"
}

# ---------------------------- 面板 HTTPS 反向代理 ------------------------------
gen_panel_caddyfile() {  # gen_panel_caddyfile <输出文件> <域名> <反代端口> <面板端口> <网关IP> [密码]
  local out="$1" dom="$2" pport="$3" wport="$4" gw="$5" pass="${6:-}"
  {
    echo "{"
    echo "	auto_https disable_redirects"
    echo "	key_type p256"
    echo "}"
    echo ""
    # 原站点: self-steal 伪装页 (Reality 目标, 必须保留)
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
    # 面板 HTTPS 反代站点
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

cmd_panel_proxy() {  # cmd_panel_proxy: bash install.sh panel-proxy -d <域名> [--panel-port <端口>] [--panel-pass <密码>]
  check_root
  [ -n "$DOMAIN_ARG" ] || die "需要 -d 指定域名: bash install.sh panel-proxy -d panel.example.com"
  command -v docker >/dev/null 2>&1 || die "Docker 未安装, 请先执行 install"
  docker ps -a --format '{{.Names}}' | grep -qx "3x-ui" || die "3X-UI 面板未安装, 请先执行 install"

  # ---- 模式 A: 复用使用该域名的前端节点 Caddy (已有证书/80端口) ----
  local line port container data_dir
  line="$(grep -v '^#' "$NODES_FILE" 2>/dev/null | grep "|${DOMAIN_ARG}$" | head -1)"
  if [ -n "$line" ]; then
    port="$(echo "$line" | cut -d'|' -f1)"
    container="$(echo "$line" | cut -d'|' -f2)"
    data_dir="$(echo "$line" | cut -d'|' -f4)"
    info "模式A: 复用前端节点 $container (端口 $port) 的 Caddy (域名 $DOMAIN_ARG)"
    docker ps --format '{{.Names}}' | grep -qx "$container" || die "前端节点 $container 未运行"

    # 读取现有容器配置, 保持一致重建
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

  # ---- 模式 B: 独立 Caddy 容器 (宿主机 80 空闲时, 无域名前端节点场景) ----
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

# ---------------------------- 节点订阅 HTTP 服务 -------------------------------
cmd_sub_server() {  # cmd_sub_server: bash install.sh sub-server [--sub-port <端口>]
  check_root
  command -v docker >/dev/null 2>&1 || die "Docker 未安装"
  [ -s "$SUB_FILE" ] || die "未找到 $SUB_FILE, 请先安装节点 (install / add-node)"
  local subdir; subdir="$(dirname "$SUB_FILE")"

  info "拉取 busybox 镜像 ..."
  ensure_image "busybox:latest"
  docker rm -f sub-server >/dev/null 2>&1 || true
  info "启动订阅 HTTP 服务 (端口 $SUB_SERVER_PORT) ..."
  docker run -d --name sub-server --restart=unless-stopped \
    -p "$SUB_SERVER_PORT:80" \
    -v "$subdir:/www:ro" \
    busybox:latest httpd -f -p 80 -h /www || die "sub-server 启动失败: docker logs sub-server"
  open_firewall "$SUB_SERVER_PORT"
  ok "订阅 HTTP 服务已启动: http://<本机IP>:$SUB_SERVER_PORT/subscription.txt"
  info "用途: 在主节点 3X-UI 面板 -> 外部订阅 中添加该 URL, 聚合此节点的节点列表"
}

# ---------------------------- 菜单 -------------------------------------------
menu() {
  while true; do
    clear 2>/dev/null || true
    banner "╔════════════════════════════════════════════════════════════╗"
    banner "║    Xray Reality (Docker) + 3X-UI 一键安装 v${VERSION}        ║"
    banner "╚════════════════════════════════════════════════════════════╝"
    echo ""
    printf "  ${C_CYAN}1)${C_RESET} 一键安装 (BBR + Docker + Reality + 3X-UI + 规则)\n"
    printf "  ${C_CYAN}2)${C_RESET} 仅 BBR + 内核网络优化\n"
    printf "  ${C_CYAN}3)${C_RESET} 仅安装 Docker\n"
    printf "  ${C_CYAN}4)${C_RESET} 仅安装 Reality 节点\n"
    printf "  ${C_CYAN}5)${C_RESET} 仅安装 3X-UI 面板\n"
    printf "  ${C_CYAN}6)${C_RESET} 添加更多 Reality 节点 (多节点)\n"
    printf "  ${C_CYAN}7)${C_RESET} 更新 v2ray-rules-dat 规则\n"
    printf "  ${C_CYAN}8)${C_RESET} 查看节点信息 / 订阅 / 二维码\n"
    printf "  ${C_CYAN}9)${C_RESET} 3X-UI 开放端口\n"
    printf "  ${C_CYAN}10)${C_RESET} 面板 HTTPS 反向代理 (Caddy)\n"
    printf "  ${C_CYAN}11)${C_RESET} 节点订阅 HTTP 服务 (供主面板聚合)\n"
    printf "  ${C_CYAN}12)${C_RESET} 卸载\n"
    printf "  ${C_CYAN}0)${C_RESET} 退出\n"
    echo ""
    printf "请选择操作: "; read -r choice
    case "$choice" in
      1)
        INSTALL_DOCKER=1; INSTALL_3XUI=1; ENABLE_BBR=1; INSTALL_RULES=1
        cmd_install; read -r -p "按回车返回菜单 ..." _
        ;;
      2) ENABLE_BBR=1; check_root; detect_os; apply_sysctl; enable_bbr
         read -r -p "按回车返回菜单 ..." _ ;;
      3) INSTALL_DOCKER=1; check_root; detect_os; install_docker; setup_docker_mirror
         read -r -p "按回车返回菜单 ..." _ ;;
      4) INSTALL_3XUI=0; INSTALL_DOCKER=1; ENABLE_BBR=0; INSTALL_RULES=1
         cmd_install; read -r -p "按回车返回菜单 ..." _ ;;
      5) INSTALL_3XUI=1; check_root; command -v docker >/dev/null 2>&1 || install_docker
         install_3xui; open_firewall "$XUI_PORT"
         read -r -p "按回车返回菜单 ..." _ ;;
      6) cmd_add_node; read -r -p "按回车返回菜单 ..." _ ;;
      7) cmd_update_rules; read -r -p "按回车返回菜单 ..." _ ;;
      8) cmd_info; read -r -p "按回车返回菜单 ..." _ ;;
      9) ask "请输入要开放的端口" ""; xui_port "$ANSWER"; read -r -p "按回车返回菜单 ..." _ ;;
      10) ask "请输入面板域名" ""; DOMAIN_ARG="$ANSWER"
          cmd_panel_proxy; read -r -p "按回车返回菜单 ..." _ ;;
      11) cmd_sub_server; read -r -p "按回车返回菜单 ..." _ ;;
      12) cmd_uninstall; read -r -p "按回车返回菜单 ..." _ ;;
      0) exit 0 ;;
      *) warn "无效选项" ;;
    esac
  done
}

# ---------------------------- 参数解析 ---------------------------------------
FORCE_RULES=0
CMD="install"
args=("$@")
if [ -n "${XRAY_ONECLICK_SOURCE_ONLY:-}" ]; then
  # 仅作为函数库被 source (测试用), 不执行任何命令
  true
else
while [ $# -gt 0 ]; do
  case "$1" in
    install) CMD="install"; shift ;;
    add-node) CMD="add-node"; shift ;;
    update-rules) CMD="update-rules"; shift ;;
    info) CMD="info"; shift ;;
    xui-port) CMD="xui-port"; shift ;;
    panel-proxy) CMD="panel-proxy"; shift ;;
    sub-server) CMD="sub-server"; shift ;;
    uninstall) CMD="uninstall"; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -p|--port) REALITY_PORT="$2"; shift 2 ;;
    -n|--network) NETWORK_MODE="$2"; shift 2 ;;
    -d|--domain) DOMAIN_ARG="$2"; shift 2 ;;
    -e|--email) ACME_EMAIL_ARG="$2"; shift 2 ;;
    -u|--uuid) UUID_ARG="$2"; shift 2 ;;
    -P|--proxy) PROXY_ARG="$2"; shift 2 ;;
    --panel-port) PANEL_PROXY_PORT="$2"; shift 2 ;;
    --panel-pass) PANEL_PROXY_PASS="$2"; shift 2 ;;
    --sub-port) SUB_SERVER_PORT="$2"; shift 2 ;;
    -x|--no-3xui) INSTALL_3XUI=0; shift ;;
    -b|--no-bbr) ENABLE_BBR=0; shift ;;
    -c|--no-docker) INSTALL_DOCKER=0; shift ;;
    -r|--no-rules) INSTALL_RULES=0; shift ;;
    -m|--mirror) USE_MIRROR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) shift ;;  # 位置参数 (如 xui-port 后的端口号) 静默跳过
  esac
done

case "$CMD" in
  install)
    if [ "$ASSUME_YES" = 0 ] && [ "${#args[@]}" = 0 ]; then
      menu
    else
      cmd_install
    fi
    ;;
  add-node) cmd_add_node ;;
  update-rules) cmd_update_rules ;;
  info) cmd_info ;;
  xui-port)
    xui_port "${args[@]:1}"
    ;;
  panel-proxy) cmd_panel_proxy ;;
  sub-server) cmd_sub_server ;;
  uninstall) cmd_uninstall ;;
esac
fi
