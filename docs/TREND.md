# 病程层（趋势）

> 一次快照只能说「谁最大」，说不了「为什么在涨」。这一层把每次采集压成一条快照，形成时间序列。

## 用法

```powershell
.\engine\winmedic.ps1 trend --record --set storage   # 记录一条快照
.\engine\winmedic.ps1 trend --record                # 记录所有探针集的最新 findings
.\engine\winmedic.ps1 trend --days 14 --top 10      # 看变化
.\engine\winmedic.ps1 trend --json
```

## 数据

只追加到 `state/trend.jsonl`，每行一条：

```json
{"ts":"2026-10-24T12:30:00+08:00","host":"DESKTOP","origin":"local","probeSet":"storage",
 "volumes":[{"drive":"C:","totalGB":237,"freeGB":93,"usedPercent":60}],
 "metrics":{"volume.freeGB":93,"storage.hiberfilGB":6.4,"workloads.totalCacheGB":2.75},
 "workloads":[{"id":"workload.steam","cacheGB":0.15}]}
```

## 置信度规则（重点）

| 情况 | confidence | 行为 |
|---|---|---|
| 少于 2 条 | `insufficient` | **不排序、不给速率**，明确提示先记录 |
| 间隔 < 0.5 天 | `low` | 给变化量，但**不给每日速率** |
| 间隔 ≥ 0.5 天 | `ok` | 给每日速率 |

这是刻意的：短间隔的抖动被当成「趋势」会误导决策。

## 为什么这是传统软件做不到的

清理工具只看「现在多大」。病程要看「过去 7 天长了多少、在哪长的」——这决定了处置是「清缓存」还是「查某个软件在疯狂写日志」。

## 建议配法

```powershell
# 每日 12:00 记录一次（注册计划任务，需管理员）
schtasks /create /tn WinMedicTrend /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\path\engine\winmedic.ps1 trend --record --set storage" /sc daily /st 12:00
```

## 已知限制

- 目录级增长需要 WizTree 导出（`scans/`），当前版本只到「域级」与「软件缓存级」
- 样本跨度不足时不会硬凑结论
- 远端快照需先在远端跑 `probe` 再 `trend --record`（或等远端趋势合并能力）
## 数据完整性（2026-10-25 修正）

病程序列曾出现两个会让结论失真的问题，现已修复：

| 问题 | 后果 | 修复 |
|---|---|---|
| 远端记录混入本机序列 | VM 的 22.9 GB 被当成宿主机的「暴跌」 | `Get-TrendRecords -Origin`；报告默认只看 `origin=local` |
| 记录时刻冒充测量时刻 | 10-23 的旧 findings 被盖上 10-25 12:00 的时间戳，看起来像当天暴跌 | `ts = findings.generatedAt`；`(origin, ts, probeSet)` 去重 |

### 查看与修复

```powershell
winmedic.ps1 trend --days 5                 # 默认只看本机
winmedic.ps1 trend --days 5 --origin all    # 含远端（会混机，仅供对照）
winmedic.ps1 trend --rebuild                # 以 findings 的测量时间为准重建序列（自动备份）
```

### 每日任务要「先采集再记录」

`scripts/trend-daily.ps1` 会先跑一次 `probe --set storage`，再 `trend --record`。直接 `trend --record` 只会复用旧 findings。
