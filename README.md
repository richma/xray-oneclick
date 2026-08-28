# Xray Reality + 3X-UI 一键安装脚本

[![CI 自动构建校验](https://github.com/richma/xray-oneclick/actions/workflows/ci.yml/badge.svg)](https://github.com/richma/xray-oneclick/actions/workflows/ci.yml)
[![每周健康检查](https://github.com/richma/xray-oneclick/actions/workflows/health-check.yml/badge.svg)](https://github.com/richma/xray-oneclick/actions/workflows/health-check.yml)
[![发布 Release](https://github.com/richma/xray-oneclick/actions/workflows/release.yml/badge.svg)](https://github.com/richma/xray-oneclick/actions/workflows/release.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

> xray reality docker 镜像前置 · BBR 内核优化 · v2ray-rules-dat 路由增强 · 3X-UI 后台 · 多节点 · 订阅/二维码 · 域名伪装

一条命令在你的服务器上部署完整的 VLESS Reality 代理节点 + 3X-UI 管理面板：

- **前置节点**：[wulabing/xray_docker_reality](https://github.com/wulabing/xray_docker) 官方镜像，端口 443 承载 VLESS Reality（`tcp`/vision 或 `xhttp`）
- **内核优化**：BBR 拥塞控制 + `fq` 队列 + 全套 TCP/UDP 内核参数（`/etc/sysctl.d/99-xray-optimize.conf`）
- **路由加强**：[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) 的 `geoip.dat` / `geosite.dat` 挂载进容器，配增强路由规则（广告拦截 `geosite:category-ads-all`、大陆直连 `geosite:cn`/`geoip:cn`、BT 拦截等），每周自动更新
- **协议伪装**：使用 [SERVERNAMES_ZH.MD](https://github.com/wulabing/xray_docker/blob/master/reality/SERVERNAMES_ZH.MD) 已知可用站点列表作为 Reality DEST/SNI，支持域名 self-steal 模式（自动签发证书并托管伪装站点）
- **3X-UI 后台**：[MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) Docker 部署，多节点管理、订阅链接、二维码、流量统计
- **多节点**：`add-node` 一条命令添加更多 Reality 节点（自动生成新 UUID/密钥，互不干扰）
- **订阅**：终端内 UTF8 二维码 + vless 链接 + 3X-UI 订阅链接，汇总文件 `subscription.txt`

---

## 快速开始

```bash
# 推荐: 下载后执行 (之后可用 bash install.sh info / add-node 等子命令)
curl -fsSL -o install.sh https://raw.githubusercontent.com/richma/xray-oneclick/main/install.sh
chmod +x install.sh
sudo bash install.sh -y          # 全自动安装 (默认参数)

# 或一行管道执行 (仅完成安装, 后续子命令请使用上面的方式)
bash <(curl -fsSL https://raw.githubusercontent.com/richma/xray-oneclick/main/install.sh) -y
```

交互式菜单：

```bash
sudo bash install.sh
```

## 常用命令

```bash
sudo bash install.sh                     # 交互式菜单
sudo bash install.sh -y                  # 全自动安装 (默认 443 端口, tcp/vision, 伪装 apple, 含 3X-UI)
sudo bash install.sh -p 8443 -n xhttp    # 自定义端口与 xhttp 网络模式
sudo bash install.sh -d vpn.example.com -e you@mail.com   # 域名 self-steal 伪装
sudo bash install.sh add-node -p 8443    # 添加第二个 Reality 节点 (多节点)
sudo bash install.sh update-rules        # 立即更新 v2ray-rules-dat 并重启节点
sudo bash install.sh info                # 查看所有节点配置/订阅/二维码
sudo bash install.sh xui-port 8388       # 3X-UI 面板内新增入站后开放端口
sudo bash install.sh panel-proxy -d panel.example.com --panel-pass 密码  # 面板 HTTPS 反代
sudo bash install.sh sub-server          # 节点订阅 HTTP 服务 (HTTP 分享节点链接)
sudo bash install.sh uninstall           # 卸载
```

## 多服务器架构（主面板管理多节点）

适合"一台主节点面板 + 多台远程节点"的部署（如 日本主 + 韩国/新加坡 节点）。利用 3X-UI 的**主从节点系统**（master 面板通过 API Token 连接子节点面板，同步入站、监控状态、提供订阅）：

```
  客户端订阅主面板地址 (http://主节点IP:2096/sub/<subid>)
                        │
                 ┌──────▼──────┐
                 │  主节点面板    │  3X-UI 主从节点系统
                 │  (master)    │
                 └──┬────────┬──┘
          API Token│        │API Token
             ┌─────▼───┐  ┌─▼─────┐
             │ 子节点面板  │  │ 子节点面板 │   各节点独立 3x-ui
             │ (SG/韩国) │  │ (…)    │
             └──────────┘  └────────┘
```

**部署步骤：**

1. **主节点**（完整安装）：`bash install.sh -y -d jp.example.com` + `bash install.sh panel-proxy -d jp.example.com`（面板 HTTPS）
2. **子节点**（每台完整安装）：`bash install.sh -y -d kr.example.com`（子节点必须有 3x-ui 才能被主面板管理）
3. **子节点生成 API Token**：子节点面板 → 面板设置 → API 令牌 → 创建（作用域 `node-sync`）
4. **主面板添加子节点**：主面板 → **节点** → 添加：填子节点地址/端口(2053)/面板路径/API Token → 保存（自动探测连通）
5. 主面板自动同步子节点入站，可查看各节点状态/延迟/流量；**所有节点的客户端订阅 URL 统一由主面板提供**
6. 客户端在主面板创建客户端获取订阅地址，或直接用各节点客户端的 subId 从主面板订阅

**一个订阅聚合所有节点（推荐，自动包含后续新增节点）**

利用 3X-UI 的 subId 非唯一特性，给**每个节点的入站都添加一个 subId 相同的共享客户端**，则该 subId 的订阅自动包含所有节点：

1. 生成一个共享 UUID
2. 在每个节点（含主节点）的 Reality 入站上添加客户端：`email=main`、`subId=main`、`flow=xtls-rprx-vision`、UUID=共享 UUID（API：`POST /panel/api/clients/add`，JSON `{"client":{...},"inboundIds":[入站ID]}`）
3. 主面板同步后，订阅（通用 `/sub/main`、Clash `/clash/main`）即包含所有节点
4. **后续新增节点（如韩国）只需在其入站添加该共享客户端 → 自动并入同一订阅，客户端无需改任何配置**

> 要求：子节点面板端口(2053)与主节点 80/8080 在云防火墙放行（Anywhere 0.0.0.0/0）；子节点与主节点间网络互通。

## 参数说明

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `-y, --yes` | 全自动安装，不询问 | 关 |
| `-p, --port <端口>` | Reality 对外端口 | `443` |
| `-n, --network <tcp\|xhttp>` | Reality 网络模式（tcp=vision / xhttp） | `tcp` |
| `-d, --domain <域名>` | 域名 self-steal 伪装（需 DNS 已指向本机，自动签 Let's Encrypt 证书） | 无 |
| `-e, --email <邮箱>` | ACME 证书邮箱（配合 `-d`） | 无 |
| `-u, --uuid <UUID>` | 自定义 UUID（默认自动生成） | 自动 |
| `-P, --proxy <URL>` | 后置代理 `socks5://` 或 `http://`（家宽 IP 解锁流媒体/AI） | 无 |
| `--panel-port <端口>` | 面板 HTTPS 反代端口（配合 `panel-proxy`） | `9443` |
| `--panel-pass <密码>` | 面板 HTTPS 反代登录密码（可选，配合 `panel-proxy`） | 无 |
| `--sub-port <端口>` | 节点订阅 HTTP 服务端口（配合 `sub-server`） | `8080` |
| `-x, --no-3xui` | 不安装 3X-UI 面板 | 装 |
| `-b, --no-bbr` | 跳过 BBR 与内核优化 | 不跳 |
| `-c, --no-docker` | 跳过 Docker 安装 | 不跳 |
| `-r, --no-rules` | 跳过 v2ray-rules-dat 下载 | 不跳 |
| `-m, --mirror` | 使用国内镜像（Docker 安装/镜像拉取/GitHub 下载） | 关 |

环境变量：`INSTALL_DIR`（默认 `/opt/xray-oneclick`）、`REALITY_IMAGE`、`XUI_IMAGE`、`XUI_PORT`（默认 `2053`）、`SHORTIDS`、`MIN_CLIENT_VER`、`PANEL_PROXY_PORT`、`PANEL_PROXY_PASS`、`SUB_SERVER_PORT`。

## 安装后

### 1. 客户端订阅 / 二维码

```bash
sudo bash install.sh info
```

会显示每个节点的：

- **vless 链接**（v2rayN / v2rayNG / sing-box 等直接扫码或复制导入）
- **终端内 UTF8 二维码**（用手机客户端扫码即可）
- 汇总订阅链接文件：`cat /opt/xray-oneclick/subscription.txt`

### 2. 3X-UI 面板

```
面板地址: http://<服务器IP>:2053/<随机路径>
默认账号: admin
默认密码: admin   (首次登录后请立即修改!)
```

面板功能：

- **入站管理**：可创建 VLESS/VMess/Trojan/Shadowsocks 等多种入站（多节点）
- **订阅**：入站列表 → 客户端 → 订阅（链接/二维码），支持 Base64 / Clash / sing-box 格式
- **统计**：在线用户、流量、连接数
- **证书**：面板设置中可配置域名 + 证书

> ⚠️ 在面板内新增入站端口后，需要在宿主机放行该端口：
> ```bash
> sudo bash install.sh xui-port 8388     # 开放面板入站端口 8388
> ```
> 3X-UI 的默认面板端口是 `2053`，与前置 Reality 节点（443）互不冲突。

### 3. 多节点

```bash
sudo bash install.sh add-node -p 8443    # 添加第二个 Reality 节点 (端口 8443)
```

每个节点独立容器、独立 UUID/密钥/端口，互不影响，`info` 与 `subscription.txt` 自动汇总所有节点。

### 4. 域名伪装（self-steal）

```bash
sudo bash install.sh -d vpn.example.com -e you@mail.com
```

- 将域名 A 记录解析到服务器 IP
- 脚本自动配置容器内置 Caddy 为域名签发证书并托管伪装站点
- Reality 的 DEST/SNI 自动切换为你的域名（"偷自己"模式），隐蔽性更高
- 如需自定义伪装页面：挂载自己的静态站点目录到容器 `/srv/www`

### 5. 面板 HTTPS 反向代理（panel-proxy）

```bash
sudo bash install.sh panel-proxy -d panel.example.com --panel-pass 你的密码
```

- 使用 Caddy 为面板签发 Let's Encrypt 证书并做反向代理（可选 `--panel-pass` 加一层登录密码）
- 访问：`https://panel.example.com:9443/<面板路径>/`
- 前端节点已配置域名时自动**复用其 Caddy**（同域名同证书，无 80 端口冲突）；否则用独立 Caddy 容器
- 要求：域名 A 记录指向本机，云防火墙放行 `80`（ACME）与 `9443`
- 修改端口：`bash install.sh panel-proxy -d panel.example.com --panel-port 2083`

## 架构说明

```
                          ┌─────────────────────────────┐
  客户端 vless://... ────► │  wulabing/xray_docker_reality │  端口 443
   (Reality TLS 握手)     │  ┌─────────────────────────┐  │
                          │  │ dokodemo-door(SNI嗅探) │  │
                          │  │   ├─ 匹配 SNI → vless-in│  │  VLESS Reality
                          │  │   └─ 不匹配  → blocked │  │  (tcp/vision | xhttp)
                          │  └─────────────────────────┘  │
                          │  Caddy (可选 self-steal 站点)  │  端口 80/8443
                          │  路由: v2ray-rules-dat 规则    │
                          └──────────────┬──────────────┘
                                         │
  管理面板 ─────────────────────────► 3X-UI (Docker)        端口 2053
  (多节点/订阅/二维码/统计)                                    + 自定入站端口
```

- 路由规则文件 `geoip.dat` / `geosite.dat` 由 [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) 发布，每日自动构建，本脚本每周三自动更新并重启节点
- 增强路由规则（`conf/xray-config.template.json`）：广告域名拦截、内网直连、大陆域名/IP 直连、BT 拦截、SNI 分流
- 伪装站点列表来自 [SERVERNAMES_ZH.MD](https://github.com/wulabing/xray_docker/blob/master/reality/SERVERNAMES_ZH.MD)

## 目录结构

```
/opt/xray-oneclick/
├── install.sh                  # 主脚本
├── nodes.ini                   # 节点注册表
├── subscription.txt            # 订阅链接汇总
├── conf/
│   ├── xray-config.template.json   # 增强路由配置模板 (v2ray-rules-dat)
│   ├── sysctl-xray.conf            # 内核优化参数
│   └── SERVERNAMES_ZH.MD           # 伪装站点列表缓存
├── rules/
│   ├── geoip.dat / geosite.dat     # v2ray-rules-dat 规则文件 (+sha256sum)
├── nodes/
│   └── node_<端口>/                # 每节点: data/(状态/配置信息) + config.json(运行时配置)
└── 3x-ui/
    ├── run.sh                      # 3X-UI 容器运行脚本
    ├── db/ cert/ acme/             # 面板数据/证书
    └── info.txt                    # 面板地址与账号信息
```

## 卸载

```bash
sudo bash install.sh uninstall
```

- 停止并删除所有节点容器与 3X-UI 容器
- 删除定时更新任务与内核优化配置
- 可选择保留/删除数据目录与 Docker

## 常见问题

**Q: 安装后连不上？**
1. 检查云厂商安全组是否放行端口（443 / 2053 / 自定义节点端口）
2. `sudo bash install.sh info` 确认节点状态为"运行中"
3. `docker logs xray_reality` 查看容器日志

**Q: 端口被占用？**
```bash
sudo bash install.sh -p 8443     # 换一个端口重新安装
```

**Q: 网络受限无法拉取镜像？**
```bash
sudo bash install.sh -m          # 使用国内镜像 (docker 镜像加速 + ghcr 镜像 + GitHub 代理)
```

**Q: 3X-UI 面板打不开？**
- 确认 `2053` 端口已放行；面板路径以 `info.txt` 中为准（首次安装会生成随机路径）
- 曾安装过 3X-UI 的服务器，路径以旧数据库为准

**Q: 如何恢复出厂/重新生成密钥？**
删除节点数据目录后重建即可：
```bash
sudo docker rm -f xray_reality
sudo rm -rf /opt/xray-oneclick/nodes/node_443
sudo bash install.sh -y
```

**Q: Clash（Mihomo）连面板 Reality 入站报 `REALITY authentication failed`？**
- 标准 xray 客户端正常但 Clash Meta/Mihomo 报认证失败 → 3x-ui 生成的新版 Reality 配置（含 `settings` 块）与 Mihomo 不兼容
- 解决：将面板入站重建为经典 Reality 配置（仅 `target/serverNames/privateKey/minClientVer/shortIds`，去掉 `settings` 块等新版字段），保留相同私钥/短ID 则客户端无需改动
- 详细步骤与配置模板见[部署与使用手册](docs/部署与使用手册.md) FAQ Q9；另请确认客户端为 **Clash Verge Rev（Mihomo 内核）**，旧版 Clash Premium 内核不支持 VLESS

## 参考项目

- [wulabing/xray_docker](https://github.com/wulabing/xray_docker) — Reality Docker 镜像
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — 代理内核
- [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) — 管理面板
- [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) — 路由规则文件

## 免责声明

本脚本仅供学习与个人合法使用，请遵守当地法律法规。请勿将 UUID、私钥等敏感信息泄露给他人。
