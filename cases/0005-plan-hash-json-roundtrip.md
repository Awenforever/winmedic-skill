# 病例 0005：apply 永远报「plan 校验失败」

## 1. 症状

- 每次 `apply --ids ... --yes` 都失败：`plan 校验失败：期望 sha256:a767…，实际 sha256:697a…`
- 表现为「防护机制太严」，实则没有任何一次真实处置能执行

## 2. 环境

| 项 | 值 |
|---|---|
| 主机 | win11-test VM（DESKTOP-GB7NLMT，管理员） |
| 引擎 | v3.1.x |

## 3. 采集（证据）

```powershell
# 同一进程内：内存计划 vs 序列化后再算
$plan = New-CdrivePlan -Findings $f
$plan.planHash                       # a767…
Get-PlanHash -Items $plan.items      # a767…  一致
$back = ($plan | ConvertTo-Json -Depth 8) | ConvertFrom-Json
Get-PlanHash -Items $back.items      # 697a…  不一致
```

两边打印的 `id|actionId|target|size|tier` 文本完全相同，差别在 **size 类型**：内存 Int64 → JSON 回读 Int32。

## 4. 假设与排除

| 假设 | 判据 | 结果 |
|---|---|---|
| 计划文件被改写 | 文件哈希与打印的一致 | 排除 |
| `-f` 格式化受区域设置影响 | 文本打印完全一致 | 排除 |
| 哈希输入不稳定（含类型） | 序列化前后哈希不同 | **支持** |

## 5. 处置

| 动作 | 影响面 | 可回滚 |
|---|---|---|
| `Get-PlanHash` 改为显式 `[int64]`/`[int]` + InvariantCulture + `v2` 前缀 | 所有计划 | 是（重新生成计划即可） |
| 补「JSON 往返后哈希不变」回归用例 | 测试 | — |

## 6. 结果

- 是否解决：是。此后 `apply` 首次真实成功，并完成 120 MB 移动 → 还原闭环
- 副作用：v2 前缀使旧计划文件失效（需重新 `plan`），已在 CHANGELOG 说明

## 7. 教训

- **安全机制的内部错误会伪装成「保护生效」**：越是被拒绝，越要怀疑是守卫自己坏了
- 哈希/签名这类逻辑必须配「序列化往返」测试——这是最容易漏、也最隐蔽的一类