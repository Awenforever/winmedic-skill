# 设计说明

## 为什么是 Skill 而不是插件或 MCP

| 形态 | 结论 | 理由 |
|---|---|---|
| DSH 插件 | 否 | 面向 Web GUI 的 npm 包，对「删文件」无增益，构建与版本耦合重 |
| MCP Server | v1 否，v2 可选 | 需要常驻进程；其「服务端强制约束」的优点可由 CLI 实现 |
| **Skill + 内置 CLI** | **是** | 判断给模型、执行给引擎；可移植到任何支持 SKILL.md 的宿主 |

关键约束：目标机只有 **Windows PowerShell 5.1**，这排除了需要 Node/npm 构建的形态。

## 四层分离

```
SKILL.md / playbook-index.md   L1 路由（懒加载，只读命中的 playbook）
playbooks/*.md                 L2 判断（决策树、话术、停手条件）
engine/                        L3 执行（探针 + 动作 + 隔离区 + 审计）
catalog/*.json                 L4 数据（探针/动作/证据的机器可读定义）
```

**硬约束：playbook 不写命令，命令只存在于 catalog 与 engine。**
这样加一个领域 = 加 playbook + 探针 + 动作 + 证据，不动路由与执行内核。

## 数据流

```
probe  -> state/findings.json  (只读，候选 + 证据引用)
plan   -> state/plan.json/.md  (分级 + 前置检查 + planHash)
apply  -> 隔离区 + journal     (哈希校验 -> 执行 -> 验证 -> 记账)
verify -> 复核可用空间与目标状态
restore-> 从隔离区移回原路径
```

## 为什么用 JSON 而不是 YAML 存 catalog

PowerShell 5.1 没有内置 YAML 解析器，引入模块会给目标机增加依赖。JSON 原生支持、可被 schema 校验、CI 友好。
（计划阶段写的是 YAML，实现时按「因地制宜」改为 JSON，已记录在 CHANGELOG。）

## 退出码

| 码 | 含义 |
|---|---|
| 0 | 成功 |
| 2 | 参数/用法错误 |
| 3 | 权限不足 |
| 4 | 前置检查未通过 |
| 5 | plan 校验失败 |
| 6 | 触碰红线 |
| 7 | 部分失败（可 restore） |