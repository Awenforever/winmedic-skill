# 目标实测台账

> 只有真机跑过 `apply → restore` 且**字节一致**的目标才算「已验证」。

## 已验证（18 个 / 40）

| 动作 | 环境 | 结果 |
|---|---|---|
| storage.edge-cache | win11-test VM | 移走 + 还原，3 文件一致 |
| storage.cbs-logs | win11-test VM | 移走 + 还原，一致 |
| storage.pip-cache | win11-test VM | 移走 + 还原，一致 |
| storage.chrome-shader-cache | win11-test VM | 移走 + 还原，一致 |
| storage.wer-reports | win11-test VM | 批量 10/10 |
| storage.crash-dumps | win11-test VM | 批量 10/10 |
| storage.npm-cache | win11-test VM | 批量 10/10 |
| storage.nuget-cache | win11-test VM | 批量 10/10 |
| storage.gradle-cache | win11-test VM | 批量 10/10 |
| storage.inetcache | win11-test VM | 批量 10/10 |
| storage.teams-cache | win11-test VM | 批量 10/10 |
| storage.chrome-service-worker | win11-test VM | 批量 10/10 |
| storage.edge-service-worker | win11-test VM | 批量 10/10 |
| storage.webcache | win11-test VM | 批量 10/10 |
| storage.wer-machine | win11-test VM | 系统类 4/4 |
| storage.delivery-optimization | win11-test VM | 系统类 4/4 |
| storage.office-file-cache | win11-test VM | 系统类 4/4 |
| storage.recycle-bin-empty | win11-test VM | 构造计划验证，移走+还原+一致 |

## 未验证（22 个）

其余动作仅在 catalog 中存在，未做真机闭环。其中：

- 浏览器类（Edge/Chrome 缓存与 GPU/Dawn 缓存）：与已验证的同类路径同构，风险低但未逐一跑
- 系统类：休眠文件（不可回滚，只做只读探测）、WINSXS（不可逆）
- 回收站：已用「构造计划」方式验证（见下）
- 开发类（HuggingFace、Slack、Adobe 媒体缓存）：依赖对应软件安装

## 复现方式

```powershell
# 单目标
winmedic.ps1 probe --set storage
winmedic.ps1 plan --set storage
winmedic.ps1 apply --ids <itemId> --yes
winmedic.ps1 restore --journal <runId>
```

批量脚本做法：为每个目标在目录内写入 25 MB 负载 → 一次 `probe`+`plan` → 逐项 `apply`+`restore` → 比对 SHA256。

## 构造计划（用于绕过体积阈值的验证）

`plan` 会过滤掉小于 20 MB 的候选，回收站常因此进不了方案。验证时可直接构造 plan.json：

```powershell
. engine\lib\Plan.ps1
$items = @([ordered]@{ id='R1'; origin='local'; actionId='storage.recycle-bin-empty'; target='C:\$Recycle.Bin'; kind='quarantine'; size=26843545; count=1; tier=1; risk='low'; reversible='full'; blocked=$false; preconditions=@(); cautions=@(); notes=''; evidence='ev.recycle-bin' })
$planHash = Get-PlanHash -Items $items
@{ schemaVersion=1; origin='local'; planHash=$planHash; items=$items } | ConvertTo-Json -Depth 8 | Set-Content plan.json
winmedic.ps1 apply --plan plan.json --ids R1 --yes
```

注意：这仅用于**测试环境**验证动作可用性，不是常规操作路径。
