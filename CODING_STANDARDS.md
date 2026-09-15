# 编码规则

改 shell 代码前先读本文件。它同时是 **code review 的 Standards 轴事实来源**：审查 diff 时逐条对照，命中就引用规则编号（如「违反 §4.2」）。

覆盖 `install.sh`、`lib/*.sh`、`test/unit-test.sh`、`scripts/*.sh`、`README.md`、`docs/部署与使用手册.md`。
规则一律用**模块名 / 函数名**定位，不写字号行号——名字稳定，行号每次改动都会漂移。

`.github/workflows/ci.yml` 是**下限**：全部脚本 `bash -n`、JSON 合法性、`realitySettings.show=false`、禁止把巨型 JSON 重新内嵌回 `install.sh`、shellcheck（提示级、不阻断）、单元测试。本文件记录 CI 管不到的约定。

---

## 1. 总则

- **1.1 幂等重跑** —— 任何子命令重复执行都收敛到同一状态，且不破坏已有客户端配置：`docker rm -f` 后再 run（`lib/07-node.sh`、`lib/08-xui.sh`）、注册表 upsert（`save_node`）、校验通过的规则文件跳过下载（`download_rules`）、`ensure_base_files` 只补缺失文件（`lib/04-files.sh`）、端口已发布则跳过（`cmd_xui_port`）、自签 Token 复用（`cmd_sub_server`）。
- **1.2 失败收口** —— 不使用 `set -e/-u/pipefail`；关键步骤显式判断。无法继续用 `die`（说明原因与补救动作），可降级用 `warn` 继续，普通失败返回非零。唯一的例外是**生成的容器脚本** `3x-ui/run.sh`——那里用 `set -e`（见 `install_3xui` 的 heredoc）。
- **1.3 可 source 可测** —— 模块顶层只做定义；`install.sh` 顶层只做「默认值 → 引导 → 加载 → 参数解析」，且仅在被 source 时提前返回（`install.sh` 末尾的 source 守卫，条件是 `XRAY_ONECLICK_SOURCE_ONLY` 已设**且** `BASH_SOURCE[0] != $0`——这样 `bash install.sh` 带该变量仍会正常解析参数）。

## 2. 模块系统

- **2.1 文件名即加载顺序** —— `lib/*.sh` 由 `install.sh` 的加载循环按字典序 source。新增模块必须选对号段：`00-04` 基础设施（输出/环境/sysctl/docker/文件）、`05-12` 功能层、`80` 放 `cmd_*` 子命令体、`91` 放 `usage` 与 `menu`。
- **2.2 顶层不做副作用** —— 所有模块在分发前一次性加载完，所以模块之间不能依赖「谁先被 source」来做顶层初始化；把逻辑放进函数，跨模块取全局时用防御性默认（`apply_sysctl` 首行的 `${ENABLE_BBR:-1}`），不要假设另一模块已赋好值。
- **2.3 每个模块首行写一行用途注释** —— 现在 `lib/*.sh` 全部具备；新增模块照做，写**模块**的职责而不是第一个函数的职责。
- **2.4 加载器的私有变量用 `_xo_` 前缀**，用完 `unset`（`install.sh` 的 `_xo_here` / `_xo_f` / `_xo_bootstrap_libs`）。

## 3. 命名与变量

- **3.1** 函数 `snake_case`；子命令入口统一 `cmd_<子命令>`（`lib/80-commands.sh`、`lib/10-panel-proxy.sh`、`lib/11-sub-server.sh`、`lib/12-cluster.sh`）。
- **3.2** 其余用 `<对象>_<动作>`（`save_node` / `node_field` / `xui_login` / `xui_insert_port_mapping` / `cluster_*_body`），谓词用 `is_` 或 `check_`（`is_valid_uuid` / `check_port_free`）。
- **3.3** 全局 `UPPER_SNAKE`；可被环境变量覆盖的写成 `VAR="${VAR:-默认}"`，默认值集中在 `install.sh` 顶部（派生路径与内部标志紧随其后）。新增可调项加在这里，不要在函数里散落字面量。
- **3.4** 函数内变量一律 `local`，参数在首行一次性取：`local port="$1" container="$2"`。
- **3.5** 引用变量一律双引号，数组用 `"${arr[@]}"`。
- **3.6 长得像不等于重复** —— 合并前先确认两者编码的**外部约束是否相同**：`raw_urls` 与 `github_release_urls`（都在 `lib/00-common.sh`）都遍历镜像列表，但前者服务 `raw.githubusercontent.com`（gitmirror 需要去掉 raw 前缀），后者服务 release 下载（gitmirror 代理不了）。合并会把约束藏到调用点背后，所以它们保持分开并在代码注释里写明原因。

## 4. 输出与交互

- **4.1** 用户可见的进度与结果只走 `info` / `ok` / `warn` / `die` / `banner`（`lib/00-common.sh`），标签固定 `[信息]` `[成功]` `[警告]` `[错误]`；只有产出数据或用 `printf` 画界面（菜单）才用裸输出。
- **4.2** `die` 只用于无法继续（非 root、不支持的系统、3X-UI 未运行）；能降级的一律 `warn` 加回退。
- **4.3** 交互走 `ask` / `ask_yn` / `confirm`（`lib/00-common.sh`），三者都先判 `ASSUME_YES`。新增询问不要直接 `read`，否则 `-y` 全自动模式会挂住。
- **4.4** 模块加载完成之前的输出（`_xo_bootstrap_libs` 阶段）用 `echo "[信息] ..." >&2`——那时 `info` 还不存在。

## 5. 错误处理

- **5.1** 外部命令先 `command -v` 再调用；预期可能失败的使用 `|| true` / `2>/dev/null`，让脚本继续。
- **5.2** 函数失败返回非零，由调用方决定怎么办；只有确实无法继续才 `die`。
- **5.3** 需要累积多个子步骤结果时用状态标志（`download_rules` 里的 `ok_all`）而不是中途 `die`。

## 6. 状态与文件

- **6.1** 节点注册表只有 `nodes.ini` 一处，格式 `端口|容器名|网络|数据目录|域名`；增删走 `save_node` / `remove_node`，不要另起一份清单。
- **6.2** 状态文件的格式与解析必须配对：`reality_config_info.txt` 是 `KEY: value`，读取一律走 `node_field`，不要另写一套解析。
- **6.3** 覆盖已有文件用「写 `.tmp` → `mv`」保证原子性（`save_node`、`xui_insert_port_mapping`）；新文件可以直接 heredoc 写。
- **6.4** 权限显式设置：生成的脚本 `chmod +x`；含密钥的文件 `umask 077` + `chmod 600`（`cmd_sub_server`、`cmd_cluster_share`）；对外订阅文件 `644`；cron `0644`。

## 7. 安全

- **7.1** 仓库内不出现真实凭据（公钥/UUID/IP/域名/密码/Token 一律占位符）。运行时产物由 `.gitignore` 兜住：`nodes/`、`rules/`、`3x-ui/`、`.xui-cookies`、`cluster-*.token`、`cluster-share.txt`、`sub-server.token`。
- **7.2** 密钥只经环境变量或命令行参数传入（`XUI_PASS` / `XUI_TOKEN` / `PANEL_PROXY_PASS` / `SUB_SERVER_TOKEN` / `NODE_TOKEN`），落到文件里的永远是变量引用；面板密码哈希后再写入配置（`caddy hash-password`）。
- **7.3** 下载物先校验再用：`sha256sum -c --status`（`download_rules`）；发布包带 `SHA256SUMS`（`scripts/pack-release.sh`）。
- **7.4** 3X-UI 面板 API 一律走 `xui_login` / `xui_api`（`lib/12-cluster.sh`），由它带 cookie 与 CSRF token。**文档里的 API 示例同样必须带 `X-CSRF-Token`**，否则照抄即失败。
- **7.5** 改文本优先用命名 helper（`xui_insert_port_mapping`）而不是内联 `sed`；确需 `sed -i` 时，地址必须限定到目标块内，不要用会命中别处的裸锚点。

## 8. 测试

- **8.1** 新增或修改函数后在 `test/unit-test.sh` 补断言，写法 `cmd; chk $? "中文描述"`（`chk` 定义在文件开头；脚本计数 `PASS/FAIL` 并以 `exit $FAIL` 结束）。
- **8.2** 测试必须能在 `debian:12` 容器、`/repo` 只读挂载下通过。写入一律落 `$INSTALL_DIR`（默认 `/tmp/xo-test`），不碰真实 `/opt` 与真实端口；环境不具备时打印 `SKIP:` 而不是 FAIL（非 root 场景同理）。
- **8.3** 需要绕开网络或容器时，用**同一 shell 内重定义函数**做桩——`download_rules() { :; }`、`docker() { case "$1" in ps) ... ;; restart) ... ;; esac; }`，配合变量注入假数据（如 `FAKE_RUNNING`）。不引入测试框架，也不用 PATH shim。
- **8.4** 覆盖关键分支而不只是顺路径：链接构建的 tcp/vision 与 xhttp/shortid 两条、`cmd_update_rules` 重启范围的面板存在/不存在两种。
- **8.5** CLI 行为变更时同步改参数测试（`cli()` 用 `env -u XRAY_ONECLICK_SOURCE_ONLY bash /repo/install.sh` 走真实入口）。

## 9. 文档

- **9.1** `docs/部署与使用手册.md` 是操作流程的唯一权威；`README.md` 只保留概览、快速开始、命令速查与参数表，细则链接手册，不整段复述同一流程。
- **9.2** 工具已封装的操作用命令表达：`cluster-share` / `cluster-add-node` 能做的事，README 不要给手工 API 步骤。
- **9.3** 示例必须可直接执行：完整请求头、完整参数、真实路径。
- **9.4** 行为变更时在**同一次提交内**更新 README 受影响描述与手册对应章节；新增规则消费方（如挂载 `geoip.dat` 的容器）要同时更新手册的规则更新章节。改动 `lib/` 结构或命名时，同样在同一次提交内更新本文件中受影响的引用。
- **9.5** 文档与注释用中文；代码、命令、专有名词与**机器可读标记**保留原文——例如 triage label 字符串（`needs-triage` 等）、`issue-tracker.md` 里被 skill 直接读取的 `PRs as a request surface:` 标记、`LICENSE` 的法律文本。

## 10. 提交与发布

- **10.1** commit message 用 `<范围>: <改动>`（范围如 `install.sh`、`lib/08-xui.sh`、`文档`、`安全`、`修复`），一次提交只做一件事，便于 review 按轴拆读。
- **10.2** 发布靠改 `install.sh` 的 `VERSION`：推送到 main 后 `release.yml` 的「解析版本并判断是否需要发版」步骤发现这个版本还没有对应 Release，就自动打 `v<VERSION>` 并上传完整包；手动推 `v*` tag 或 Run workflow 是补发通道，不要用它绕过流程。

## 11. 已收敛项与风格并存

本文件首次落盘时记录的偏差已处理，留档以免重复讨论：

- **已收敛**：模块头注释不统一 → 现在 `lib/*.sh` 全部有一行模块用途注释（§2.3）；`xui_port` 缺 `cmd_` 前缀 → 改名 `cmd_xui_port`（§3.1）；`raw_urls` 与 `github_release_urls` 疑似重复 → 判定为不合并，原因写进代码注释并立为 §3.6。
- **仍并存，不视为偏差**：菜单用裸 `printf` 画界面、少数结果输出用裸 `echo`（`lib/91-menu.sh`、`lib/12-cluster.sh`、`lib/80-commands.sh`），符合 §4.1 的「数据/界面输出」例外；`enable_bbr` 用 `sed -i` 改已存在的系统配置文件，符合 §7.5。
