# 难例清单

## 引擎级（H 系列）

| # | 难例 | 期望 | 状态 |
|---|---|---|---|
| H1 | `Test-Path` 对 hiberfil/pagefile 假阴性 | 用 `dir /a:hs` 解析 | 已实现 |
| H2 | Package Cache 实为 Intel 驱动 | 读 readme 才判 | 已实现 |
| H3 | WinSxS 清理后空间反降 | 标 pendingReboot，不判失败 | 已实现 |
| H4 | 提交上限不足 | 前置检查 `commit-headroom:N` 拦截 | 已实现 + 单测（无自动缩页面文件动作，刻意保守） |
| H5 | 硬链接口径失真 | 报告用 allocated | 部分（WizTree 索引） |
| H6 | 隔离区同名冲突 | 冲突时加后缀 | 已实现 |
| H7 | 非管理员 apply | 码 3 | 已实现 |
| H8 | plan 被篡改 | 码 5 | 已实现 + 单测 |
| H9 | 用户排除项 | plan 排除 + apply 二次拦截 | 已实现 + 单测 |
| H10 | 目标被占用 | 跳过并记账 | 已实现（移动失败记 error 并继续） |
| H11 | 中文/emoji | 无 emoji、无乱码 | 已实现 |
| H12 | apply 中途 kill | journal 完整可 restore | 已实现（JSONL 逐条） |
| H13 | plan 指向 WinSxS | 码 6 | 已实现 + 单测 |
| H14 | 重复执行幂等 | 第二次 skipped | 已实现 + 单测（`mode=absent` 记 skipped） |

## 路由级（R 系列）

| # | 说法 | 期望 | 状态 |
|---|---|---|---|
| R1 | C 盘红了 | storage-disk-space-recovery | 已覆盖 |
| R2 | 开机特别慢 | boot-slow-boot-triage | 已覆盖 |
| R3 | 把微信迁到 D 盘 | apps-migrate（不得当清理） | 已覆盖 |
| R4 | 全删了吧 | 拒绝 + cleanup-protocol | 已覆盖 |
| R5 | 蓝屏进不去系统 | 恢复分诊 + 离线限制 | v1.4 |
| R6 | 有点卡，顺便清下盘 | 多目标，先诊断后清理 | 已在 SKILL.md 规定 |

## 真机验收

记录模板见 `tests/lab/Win11-Lab.md`。要求：至少 2 台真机各做 1 项低风险动作 + verify + restore。