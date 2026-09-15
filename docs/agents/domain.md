# 领域文档

工程类 skill 在探索本仓库代码时，应如何消费本仓库的领域文档。

## 探索之前先读

- 仓库根目录的 **`CONTEXT.md`**，或
- 仓库根目录的 **`CONTEXT-MAP.md`**（若存在）——它指向每个上下文各自的 `CONTEXT.md`，读其中与当前主题相关的那些。
- **`docs/adr/`**——读与你要动的区域相关的 ADR。多上下文仓库还要看 `src/<context>/docs/adr/` 里上下文专属的决策。

以上文件不存在就**静默继续**：不要指出它们缺失，也不要一上来就建议创建。`/domain-modeling` skill（经 `/grill-with-docs` 与 `/improve-codebase-architecture` 抵达）会在术语或决策真正定下来时按需创建它们。

## 文件结构

单上下文仓库（多数仓库）：

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多上下文仓库（根目录存在 `CONTEXT-MAP.md`）：

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← 系统级决策
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← 上下文专属决策
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## 使用术语表里的词汇

输出内容提到领域概念时（issue 标题、重构提案、假设、测试名），使用 `CONTEXT.md` 中定义的术语，不要漂移到术语表明确回避的同义词。

如果需要用到的概念还不在术语表里，这本身就是信号：要么你在发明项目并不使用的说法（重新考虑），要么存在真实的空白（记下来交给 `/domain-modeling`）。

## 标出 ADR 冲突

如果你的输出与现有 ADR 矛盾，明确说出来，不要默默覆盖：

> _与 ADR-0007 (event-sourced orders) 冲突——但值得重开，因为……_
