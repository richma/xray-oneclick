# 安全说明

## 报告漏洞

请不要在公开 Issue 里贴节点 UUID、Reality 公钥/私钥、面板密码或 API Token。
发邮件到仓库所有者 `richma@126.com`，或开一个**不含密钥**的私密说明。

## 已知风险与处置

### Git 历史中的示例凭据（已从当前文档移除，但仍在旧 commit 中）

提交 `f659558` 之前，`docs/部署与使用手册.md` 里出现过真实部署痕迹：

| 类型 | 值 | 说明 |
| --- | --- | --- |
| UUID | `0acc8b47-2bf8-4f9b-a00c-aeaf10d9c785` | 文档示例，可能来自真实节点 |
| Reality 公钥 | `71VRtghYOyObxa05Xy6DFOR06Vhulj7e9W0o9ErV0SQ` | 文档示例 |
| IPv4 | `54.169.141.34` | 文档中的子节点 IP 示例 |

公开仓库的 git 历史无法靠“改当前文件”抹掉。若上述凭据曾用于仍在线的节点，请**立刻轮换 UUID / Reality 密钥对**，并检查该 IP 的安全组是否仍对公网开放管理端口。

不建议对已发布 tag 的公开仓库强行 `git filter-repo`，除非你明确接受所有 fork/clone 失效。

### GitHub 仓库安全功能（2026-09-03）

已打开：

- Secret scanning
- Secret scanning push protection
- Dependabot vulnerability alerts
- Dependabot security updates

仍可选：Code scanning（本仓库以 Shell 为主，收益有限）。

本仓库已做的加固：

- Actions 使用 commit SHA 固定 `checkout` / `github-script` / `action-gh-release`
- `.github/dependabot.yml` 跟踪 GitHub Actions 更新
- 运行时密钥写入 `/opt/xray-oneclick/`，`.gitignore` 排除节点数据、cookie、token
- `sub-server` 使用随机 URL 路径令牌，不再裸奔 `/subscription.txt`
- Reality 模板 `show: false`，避免握手调试信息进日志
- Docker `daemon.json` 合并镜像源，不再整文件覆盖

### 部署后必做

1. 立刻修改 3X-UI 默认 `admin` / `admin`
2. 不要把 `cluster-*.token`、`sub-server.token`、`reality_config_info.txt` 提交到 git
3. 面板 2053 不要对 `0.0.0.0/0` 长期开放；优先 `panel-proxy` + 强密码
4. `cluster-token` 只显示一次，文件权限应为 `600`
