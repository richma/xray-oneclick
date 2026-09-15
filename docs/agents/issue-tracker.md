# Issue tracker: GitHub

本仓库的 issue 与 spec 都以 GitHub issue 的形式存在。所有操作使用 `gh` CLI。

## 约定

- **新建 issue**：`gh issue create --title "..." --body "..."`。多行正文用 heredoc。
- **读取 issue**：`gh issue view <number> --comments`，用 `jq` 过滤评论，并一并取 labels。
- **列出 issue**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，配合相应的 `--label` 与 `--state` 过滤。
- **评论**：`gh issue comment <number> --body "..."`
- **加 / 去 label**：`gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **关闭**：`gh issue close <number> --comment "..."`

仓库由 `git remote -v` 推断——在 clone 内运行时 `gh` 会自动处理。

## PR 是否作为 triage 入口

**PRs as a request surface: no.**

_上一行是 `/triage` 直接读取的机器标记，必须保持英文原样（含义：外部 PR 不作为功能请求入口）；若本仓库把外部 PR 当功能请求，把它改成 `yes`。_

设为 `yes` 时，PR 走与 issue 相同的 labels 与状态，用 `gh pr` 的对应命令：

- **读取 PR**：`gh pr view <number> --comments`；diff 用 `gh pr diff <number>`。
- **列出待 triage 的外部 PR**：`gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`，然后只保留 `authorAssociation` 为 `CONTRIBUTOR`、`FIRST_TIME_CONTRIBUTOR`、`NONE` 的（丢掉 `OWNER`/`MEMBER`/`COLLABORATOR`）。
- **评论 / 打 label / 关闭**：`gh pr comment`、`gh pr edit --add-label`/`--remove-label`、`gh pr close`。

GitHub 的 issue 与 PR 共用同一套编号空间，所以孤立的 `#42` 可能是任一种——先用 `gh pr view 42` 解析，失败再退回 `gh issue view 42`。

## 当某个 skill 说“publish to the issue tracker”

就是新建一个 GitHub issue。

## 当某个 skill 说“fetch the relevant ticket”

执行 `gh issue view <number> --comments`。

## Wayfinding 操作

供 `/wayfinder` 使用。**map** 是一个 issue，**child** issue 充当 ticket。

- **Map**：打上 `wayfinder:map` label 的单个 issue，正文承载 Notes / Decisions-so-far / Fog。`gh issue create --label wayfinder:map`。
- **Child ticket**：作为 GitHub sub-issue 关联到 map（对 sub-issues 端点调 `gh api`）。未启用 sub-issue 时，把 child 加进 map 正文的任务列表，并在 child 正文顶部写 `Part of #<map>`。Labels：`wayfinder:<type>`（`research`/`prototype`/`grilling`/`task`）。被认领后把 ticket 指派给执行的开发者。
- **Blocking**：用 GitHub 原生的 issue dependencies——这是规范且 UI 可见的表达。加边：`gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`，其中 `<blocker-db-id>` 是阻塞方的数字**数据库 id**（`gh api repos/<owner>/<repo>/issues/<n> --jq .id`，**不是** `#number`，也不是 `node_id`）。GitHub 会报告 `issue_dependencies_summary.blocked_by`（只含未关闭的阻塞方——即实时闸门）。依赖功能不可用时，退回在 child 正文顶部写一行 `Blocked by: #<n>, #<n>`。所有阻塞方都关闭后，ticket 即为 unblocked。
- **Frontier 查询**：列出 map 下处于 open 的 child（`gh issue list --state open`，范围限定在 map 的 sub-issues / 任务列表），丢掉有未关闭阻塞方（`issue_dependencies_summary.blocked_by > 0`，或 `Blocked by` 行里还有 open 的 issue）或已有 assignee 的；按 map 顺序取第一个。
- **Claim**：`gh issue edit <n> --add-assignee @me`——这是本次会话的第一次写入。
- **Resolve**：`gh issue comment <n> --body "<answer>"`，然后 `gh issue close <n>`，再把上下文指针（gist + 链接）追加到 map 的 Decisions-so-far。
