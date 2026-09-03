#!/usr/bin/env bash
# ==============================================================================
#  Xray Reality (Docker 前置) + 3X-UI 一键安装脚本
#  逻辑在 lib/*.sh; 本文件负责默认值、加载模块、参数解析。
#  curl | bash 时若旁边没有 lib/, 会从 GitHub 拉取对应版本的完整仓库。
# ==============================================================================

VERSION="1.1.0"
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
SUB_SERVER_TOKEN="${SUB_SERVER_TOKEN:-}"
XRAY_ONECLICK_REPO="${XRAY_ONECLICK_REPO:-https://github.com/richma/xray-oneclick}"

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
FORCE_RULES=0

REALITY_PORT=""
NETWORK_MODE=""
DEST_ARG=""
SERVERNAMES_ARG=""
DOMAIN_ARG=""
ACME_EMAIL_ARG=""
PROXY_ARG=""
UUID_ARG=""
XUI_PORTS=()

XUI_USER="${XUI_USER:-admin}"
XUI_PASS="${XUI_PASS:-admin}"
XUI_TOKEN="${XUI_TOKEN:-}"
NODE_NAME=""
NODE_ADDRESS=""
NODE_PORT=""
NODE_PATH=""
NODE_TOKEN=""
NODE_SCHEME="http"
NODE_SYNC="all"
NODE_ALLOW_PRIVATE=0
NODE_TLS_SKIP=1
SHARE_EMAIL="main"
SHARE_SUBID="main"
SHARE_UUID=""
HOST_INBOUND=""
HOST_ADDR=""
HOST_REMARK=""
HOST_SNI=""
HOST_FINGERPRINT="chrome"

_xo_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

_xo_bootstrap_libs() {
  local tmp tarball ref
  tmp="${TMPDIR:-/tmp}/xray-oneclick-src-$$"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  tarball="$tmp/src.tar.gz"
  echo "[信息] 未找到 lib/, 正在下载完整仓库 ..." >&2
  local urls=()
  for ref in ${XRAY_ONECLICK_REF:-} "v${VERSION}" "main"; do
    [ -n "$ref" ] || continue
    urls+=("${XRAY_ONECLICK_REPO}/archive/refs/tags/${ref}.tar.gz")
    urls+=("${XRAY_ONECLICK_REPO}/archive/refs/heads/${ref}.tar.gz")
    local m
    for m in "${GITHUB_RAW_MIRRORS[@]}"; do
      case "$m" in
        *gitmirror*) ;;
        *)
          urls+=("${m}${XRAY_ONECLICK_REPO}/archive/refs/tags/${ref}.tar.gz")
          urls+=("${m}${XRAY_ONECLICK_REPO}/archive/refs/heads/${ref}.tar.gz")
          ;;
      esac
    done
  done
  local u ok=0
  for u in "${urls[@]}"; do
    if curl -fsSL --connect-timeout 10 --max-time 120 -o "$tarball" "$u" 2>/dev/null; then
      ok=1
      break
    fi
  done
  [ "$ok" = 1 ] || { echo "[错误] 无法下载仓库 (需要 lib/). 请 git clone 后执行." >&2; exit 1; }
  tar -tzf "$tarball" >/dev/null 2>&1 || { echo "[错误] 仓库压缩包损坏" >&2; exit 1; }
  tar -xzf "$tarball" -C "$tmp"
  local extracted
  extracted="$(find "$tmp" -maxdepth 1 -type d -name 'xray-oneclick-*' | head -1)"
  [ -d "$extracted/lib" ] || { echo "[错误] 压缩包内没有 lib/" >&2; exit 1; }
  SCRIPT_DIR="$extracted"
}

if [ -d "${_xo_here}/lib" ]; then
  SCRIPT_DIR="$_xo_here"
elif [ -n "${SCRIPT_DIR:-}" ] && [ -d "$SCRIPT_DIR/lib" ]; then
  :
else
  SCRIPT_DIR="${_xo_here:-.}"
  _xo_bootstrap_libs
fi

# shellcheck disable=SC1090
for _xo_f in "$SCRIPT_DIR"/lib/*.sh; do
  [ -f "$_xo_f" ] || continue
  # shellcheck disable=SC1091
  . "$_xo_f"
done
unset _xo_f

# 仅当被 source 时跳过 CLI (测试用). 直接 bash install.sh 即使带该环境变量也要解析参数.
if [ -n "${XRAY_ONECLICK_SOURCE_ONLY:-}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

CMD="install"
args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    install) CMD="install"; shift ;;
    add-node) CMD="add-node"; shift ;;
    update-rules) CMD="update-rules"; shift ;;
    info) CMD="info"; shift ;;
    xui-port)
      CMD="xui-port"; shift
      while [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; do
        XUI_PORTS+=("$1"); shift
      done
      ;;
    panel-proxy) CMD="panel-proxy"; shift ;;
    sub-server) CMD="sub-server"; shift ;;
    cluster-token) CMD="cluster-token"; shift ;;
    cluster-add-node) CMD="cluster-add-node"; shift ;;
    cluster-share) CMD="cluster-share"; shift ;;
    cluster-host) CMD="cluster-host"; shift ;;
    cluster-status) CMD="cluster-status"; shift ;;
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
    --sub-token) SUB_SERVER_TOKEN="$2"; shift 2 ;;
    --xui-user) XUI_USER="$2"; shift 2 ;;
    --xui-pass) XUI_PASS="$2"; shift 2 ;;
    --xui-token) XUI_TOKEN="$2"; shift 2 ;;
    --node-name) NODE_NAME="$2"; shift 2 ;;
    --node-address) NODE_ADDRESS="$2"; shift 2 ;;
    --node-port) NODE_PORT="$2"; shift 2 ;;
    --node-path) NODE_PATH="$2"; shift 2 ;;
    --node-token) NODE_TOKEN="$2"; shift 2 ;;
    --node-scheme) NODE_SCHEME="$2"; shift 2 ;;
    --share-email) SHARE_EMAIL="$2"; shift 2 ;;
    --share-subid) SHARE_SUBID="$2"; shift 2 ;;
    --share-uuid) SHARE_UUID="$2"; shift 2 ;;
    --host-inbound) HOST_INBOUND="$2"; shift 2 ;;
    --host-addr) HOST_ADDR="$2"; shift 2 ;;
    --host-remark) HOST_REMARK="$2"; shift 2 ;;
    --host-sni) HOST_SNI="$2"; shift 2 ;;
    --allow-private) NODE_ALLOW_PRIVATE=1; shift ;;
    --tls-verify) NODE_TLS_SKIP=0; shift ;;
    -x|--no-3xui) INSTALL_3XUI=0; shift ;;
    -b|--no-bbr) ENABLE_BBR=0; shift ;;
    -c|--no-docker) INSTALL_DOCKER=0; shift ;;
    -r|--no-rules) INSTALL_RULES=0; shift ;;
    -m|--mirror) USE_MIRROR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1 (见 --help)" ;;
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
    [ "${#XUI_PORTS[@]}" -gt 0 ] || die "用法: bash install.sh xui-port <端口> [更多端口]"
    xui_port "${XUI_PORTS[@]}"
    ;;
  panel-proxy) cmd_panel_proxy ;;
  sub-server) cmd_sub_server ;;
  cluster-token) cmd_cluster_token ;;
  cluster-add-node) cmd_cluster_add_node ;;
  cluster-share) cmd_cluster_share ;;
  cluster-host) cmd_cluster_host ;;
  cluster-status) cmd_cluster_status ;;
  uninstall) cmd_uninstall ;;
  *) die "未知子命令: $CMD" ;;
esac
