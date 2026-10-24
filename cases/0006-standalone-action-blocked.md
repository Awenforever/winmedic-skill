# 病例 0006：`apply --action` 永远提示「找不到 plan」

## 1. 症状

- `apply --action recovery.create-restore-point --yes` → `找不到 plan：…\state\plan.json`
- 但建议层（`rec.restore-point`）一直在推荐「先建还原点」

## 2. 环境

| 项 | 值 |
|---|---|
| 主机 | win11-test VM（管理员） |
| 引擎 | v3.2.0 |

## 3. 采集（证据）

```powershell
winmedic.ps1 apply --action recovery.create-restore-point --yes
# [X] 找不到 plan：C:\...\state\plan.json   exit=2
```

代码顺序：`Invoke-Apply` 先检查 plan 存在性 → 再检查 `--ids` → 才进入 standalone 分支。

## 4. 假设与排除

| 假设 | 判据 | 结果 |
|---|---|---|
| 动作未在 catalog 标注 standalone | catalog 里 `standalone: true` | 排除 |
| 缺少管理员 | 该机 isAdmin=True | 排除 |
| **前置校验顺序错误** | plan 检查在 standalone 分支之前 | **支持** |

## 5. 处置

| 动作 | 影响面 | 可回滚 |
|---|---|---|
| standalone 分支提到函数最前，只要求 `--yes` | apply 入口 | 是 |
| 校验顺序：动作存在 → standalone → Tier → 权限 | 错误码语义 | — |

## 6. 结果

- 是否解决：是。`create-restore-point` 真实执行成功（67 秒，exit 0），journal 有 begin/done
- 回归曾抓到「非管理员下未知动作返回 3 而非 2」，已调整顺序修复

## 7. 教训

- **分支被主流程的前置检查挡住**是典型死代码；判断「某功能有没有跑过」只需看 journal 有没有对应记录