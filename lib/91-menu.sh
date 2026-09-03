usage() {
  cat <<EOF
Xray Reality + 3X-UI 一键安装脚本 v${VERSION}

用法: bash install.sh [子命令] [选项]

子命令:
  install            执行安装 (默认)
  add-node           添加更多本机 Reality 前置节点
  update-rules       更新 v2ray-rules-dat 并重启节点
  info               查看前置节点信息 / 订阅 / 二维码
  xui-port <p>       为 3X-UI 面板开放新端口
  panel-proxy        面板 HTTPS 反向代理: -d <域名> [--panel-port] [--panel-pass]
  sub-server         节点订阅 HTTP 服务 (带随机路径令牌)
  cluster-token      子节点: 登录面板并签发 node-sync Token
  cluster-add-node   主节点: 注册子节点
  cluster-share      本机面板: 给全部入站添加共享 subId 客户端
  cluster-host       本机面板: 为入站覆盖订阅 Host
  cluster-status     主节点: 列出已注册子节点
  uninstall          卸载全部组件

选项:
  -y, --yes            全自动安装, 使用默认值不询问
  -p, --port <端口>    Reality 对外端口 (默认 443)
  -n, --network <模式> Reality 网络模式: tcp(vision) 或 xhttp (默认 tcp)
  -d, --domain <域名>  域名 self-steal 模式
  -e, --email <邮箱>   ACME 证书邮箱 (配合 -d)
  -u, --uuid <UUID>    自定义 UUID (默认自动生成)
  -P, --proxy <URL>    后置代理 socks5:// 或 http://
  --panel-port <端口>  面板 HTTPS 反代端口 (默认 9443)
  --panel-pass <密码>  面板 HTTPS 反代登录密码
  --sub-port <端口>    订阅 HTTP 服务端口 (默认 8080)
  --sub-token <令牌>   订阅 URL 路径令牌 (默认随机)
  --xui-user <用户>    面板登录用户 (默认 admin)
  --xui-pass <密码>    面板登录密码 (默认 admin)
  --xui-token <Token>  面板 Bearer Token (优先于用户名密码)
  --node-name <名称>   cluster-add-node: 子节点名称
  --node-address <主机> cluster-add-node: 子节点地址
  --node-port <端口>   cluster-add-node: 子节点面板端口 (默认 2053)
  --node-path <路径>   cluster-add-node: 子节点面板路径
  --node-token <Token> cluster-add-node: 子节点 node-sync Token
  --node-scheme <http|https>
  --share-email <邮箱> cluster-share: 共享客户端 email (默认 main)
  --share-subid <id>   cluster-share: 共享 subId (默认 main)
  --share-uuid <UUID>  cluster-share: 共享 UUID (默认新生成)
  --host-inbound <id>  cluster-host: 入站 ID
  --host-addr <主机>   cluster-host: 覆盖地址 (可带 :端口)
  --host-remark <备注>
  --allow-private      允许主面板连接私网地址的子节点
  --tls-verify         HTTPS 子节点校验证书 (默认 skip)
  -x, --no-3xui        不安装 3X-UI 面板
  -b, --no-bbr         跳过 BBR 与内核优化
  -c, --no-docker      跳过 Docker 安装 (已安装时)
  -r, --no-rules       跳过 v2ray-rules-dat 下载
  -m, --mirror         使用国内镜像加速 (docker/ghcr/github)
  -h, --help           显示帮助
EOF
}

menu() {
  while true; do
    clear 2>/dev/null || true
    banner "╔════════════════════════════════════════════════════════════╗"
    banner "║    Xray Reality (Docker) + 3X-UI 一键安装 v${VERSION}        ║"
    banner "╚════════════════════════════════════════════════════════════╝"
    echo ""
    printf "  ${C_CYAN}1)${C_RESET} 一键安装 (BBR + Docker + Reality 前置 + 3X-UI + 规则)\n"
    printf "  ${C_CYAN}2)${C_RESET} 仅 BBR + 内核网络优化\n"
    printf "  ${C_CYAN}3)${C_RESET} 仅安装 Docker\n"
    printf "  ${C_CYAN}4)${C_RESET} 仅安装 Reality 前置节点\n"
    printf "  ${C_CYAN}5)${C_RESET} 仅安装 3X-UI 面板\n"
    printf "  ${C_CYAN}6)${C_RESET} 添加更多本机 Reality 前置节点\n"
    printf "  ${C_CYAN}7)${C_RESET} 更新 v2ray-rules-dat 规则\n"
    printf "  ${C_CYAN}8)${C_RESET} 查看前置节点信息 / 订阅 / 二维码\n"
    printf "  ${C_CYAN}9)${C_RESET} 3X-UI 开放端口\n"
    printf "  ${C_CYAN}10)${C_RESET} 面板 HTTPS 反向代理 (Caddy)\n"
    printf "  ${C_CYAN}11)${C_RESET} 节点订阅 HTTP 服务\n"
    printf "  ${C_CYAN}12)${C_RESET} 集群: 签发子节点 Token\n"
    printf "  ${C_CYAN}13)${C_RESET} 集群: 主面板添加子节点\n"
    printf "  ${C_CYAN}14)${C_RESET} 集群: 共享订阅客户端\n"
    printf "  ${C_CYAN}15)${C_RESET} 集群: 查看子节点状态\n"
    printf "  ${C_CYAN}16)${C_RESET} 卸载\n"
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
      9) ask "请输入要开放的端口" ""; xui_port $ANSWER; read -r -p "按回车返回菜单 ..." _ ;;
      10) ask "请输入面板域名" ""; DOMAIN_ARG="$ANSWER"
          cmd_panel_proxy; read -r -p "按回车返回菜单 ..." _ ;;
      11) cmd_sub_server; read -r -p "按回车返回菜单 ..." _ ;;
      12) cmd_cluster_token; read -r -p "按回车返回菜单 ..." _ ;;
      13) ask "子节点名称" ""; NODE_NAME="$ANSWER"
          ask "子节点地址" ""; NODE_ADDRESS="$ANSWER"
          ask "子节点面板端口" "$XUI_PORT"; NODE_PORT="$ANSWER"
          ask "子节点面板路径" "/"; NODE_PATH="$ANSWER"
          ask "子节点 node-sync Token" ""; NODE_TOKEN="$ANSWER"
          cmd_cluster_add_node; read -r -p "按回车返回菜单 ..." _ ;;
      14) cmd_cluster_share; read -r -p "按回车返回菜单 ..." _ ;;
      15) cmd_cluster_status; read -r -p "按回车返回菜单 ..." _ ;;
      16) cmd_uninstall; read -r -p "按回车返回菜单 ..." _ ;;
      0) exit 0 ;;
      *) warn "无效选项" ;;
    esac
  done
}
