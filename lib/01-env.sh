check_root() {
  [ "$(id -u)" = 0 ] || die "请以 root 权限运行: sudo bash install.sh"
}

detect_os() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
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
