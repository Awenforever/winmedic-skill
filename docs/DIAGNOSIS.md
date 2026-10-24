# 鉴别诊断与器械台

> 这一层回答的是：**「主治医生会怎么查」**。
> 引擎只摆事实，结论由 Agent 下——这是 v2.4 定下的分工，不变。

## 鉴别诊断

```powershell
.\engine\winmedic.ps1 diagnose --list
.\engine\winmedic.ps1 diagnose --case dx.cdisk-full
```

输出结构（`--json` 同构）：

```json
{ "case": "dx.cdisk-full",
  "hypotheses": [{ "id": "h.hiberfil", "name": "休眠文件占用", "why": "...",
                   "checks": [{ "metric": "storage.hiberfilGB", "signal": ">4 GB 视为显著",
                                "currentValue": 0, "available": true, "source": "snapshot" }] }],
  "facts": [ ... ],
  "missingProbes": ["probe.workloads"] }
```

**刻意不包含** `verdict` / `status` / `conclusion` 字段——有单测断言其不存在。

### 数据来源

| source | 含义 |
|---|---|
| `snapshot` | 当前 findings 的绝对值 |
| `trend:7d` | 7 天窗口内的变化量（速率可用） |
| `trend:low(仅变化量...)` | 变化量可用，但样本间隔 <0.5 天，**不能推速率** |
| `trend:insufficient` | 样本不足，**无值** |

### 选哪份 findings

不是盲目用最新，而是选**对本次诊断覆盖最全**的那份；覆盖不足会告警并列出缺失探针。

## 器械台

```powershell
.\engine\winmedic.ps1 tools
.\engine\winmedic.ps1 tools --json
```

每个器械登记：检测方式（命令/路径/注册表）、静默参数、风险级别（Tier 1-4）、是否可回滚、说明。

首批：WizTree、DISM、PnPUtil、netsh、winget、ssh、scp、wevtutil。

**只检测与说明，不执行高危动作**；Tier ≥ 3（如 DISM 组件清理）必须由 Agent 显式计划后再调用。

## 新增一个诊断用例

在 `catalog/diagnoses.json` 加一条：`requiredProbes` + `hypotheses[].checks[{metric, signal, days?}]`；
`metric` 取自趋势快照的指标键（见 `docs/TREND.md`）。`validate-catalog.ps1` 会强制检查结构。
