## 语言要求

本工作区一律使用简体中文对话：所有回复、提问、解释与状态说明均用中文。代码、命令、文件路径与标识符保持原文，不翻译。

## Agent skills

### Issue 跟踪

Issue 存放在本仓库的 GitHub Issues（用 `gh` CLI）。见 `docs/agents/issue-tracker.md`。

### Triage 标签

规范角色沿用默认字符串：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`。见 `docs/agents/triage-labels.md`。

### 领域文档

单上下文（single-context）：根目录 `CONTEXT.md` + `docs/adr/`。见 `docs/agents/domain.md`。

### 编码规则

改 shell 代码或审查 diff 前先读 `CODING_STANDARDS.md`：它记录了 `lib/` 模块的约定，review 结论引用其规则编号。
