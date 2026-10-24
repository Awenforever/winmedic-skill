---
name: winmedic
description: Windows 电脑维修：诊断、清理、迁移、修复。覆盖磁盘空间、开机与性能、应用生命周期、更新与驱动、网络、安全态势、恢复分诊。只读优先，破坏性动作走隔离区并支持回滚，每条建议附证据。
whenToUse: 用户说 C 盘爆满/变红、电脑卡顿、开机慢、软件卸不干净、想把微信或应用到 D 盘、大目录治理、更新失败、驱动异常、断网、蓝屏、误删文件、新机验收等需要「检查或改动本机 Windows」的请求。 English keywords: disk full, low disk space, slow boot, startup bloat, uninstall leftovers, migrate app or data to another drive, Windows Update failure, driver or device problem, no internet, proxy/VPN issue, printer offline, backup check, recover deleted files, new PC intake.
version: 1.16.0
---

# WinMedic

## 目标

把宿主 Agent 当推理层，把本机 PowerShell 和内置引擎当执行层。**先用证据定位原因，再提最小修复，确认后执行并验证。**

本 Skill 不启动独立模型、不联网、不采集遥测，始终服从宿主的权限与审批机制。

## 执行前检查

1. 确认平台是 Windows、Shell 是 PowerShell、当前是否管理员。**不要凭用户描述推断。**
2. 确认作用范围是本机。用户给了保留项（不要动微信、别删 D 盘）就写成约束，全程遵守。
3. 运行 `engine\winmedic.ps1 doctor` 一次，拿到权限/PS 版本/WizTree 可用性。
4. 若宿主无本机执行能力（只有聊天），改用「人工步骤 + 验证点」模式输出，不假装执行。

## 强制工作流

### 1. 明确目标

- 拆成：症状、期望状态、不可改变的约束。
- 多目标逐项保留，**不得用删除替代迁移、用重装替代修复**。
- 只有歧义会显著改变路径时才提问。

### 2. 路由 Playbook

- 读 [playbook-index.md](playbook-index.md)，按症状选**最具体**的一个。
- **只加载需要的那一份** `playbooks/*.md`，不要一次读全部。
- 多个独立问题时，按「影响面 × 依赖顺序」逐个做。

### 3. 只读诊断

```powershell
winmedic.ps1 probe --set <domain>        # 产出 state\findings.json
```

- 探针只读。任何一步产生写操作都是 bug，立即停止并报告。
- 采不到的项如实标注「无法获取」，不要猜。

### 4. 生成方案

```powershell
winmedic.ps1 plan --from state\findings.json
```

输出 `plan.json` + `plan.md` + `planHash`。**把 plan.md 原文呈现给用户**，不要自己复述成模糊描述。

plan.md 现在含两段：

1. **建议（按优先级）** —— 跨域处置建议，`high` 先处理（待重启、无还原点、安全风险、磁盘告急）
   - `处置` 列写 `可执行: <action>` 的，可直接 `winmedic.ps1 apply --action <action> --yes`
   - 写 `人工: <playbook>` 的，按该 playbook 逐条处置，**不要自己发明步骤**
2. **明细** —— 引擎可执行的清理项（按 id 执行）

建议段的来源是确定性规则（不是模型猜测），证据指向 playbook 或 catalog 证据条目。

### 5. 确认

- 逐项列出：动作、影响量、风险级别、能否回滚。
- **只执行用户点过头的 id**。用户说「都行」时，默认只做 Tier 1 + Tier 2。
- Tier 3 必须逐项确认；Tier 4 一律不执行。

### 6. 执行

```powershell
winmedic.ps1 apply --plan state\plan.json --ids R1,R3 --yes
```

- 默认进隔离区（soft delete），**不要**随手加 `--purge`。
- 部分失败（退出码 7）时，先看 journal 再决定是否继续。

### 7. 验证

```powershell
winmedic.ps1 verify --journal <id>
```

- 核对可用空间、服务状态、目标是否消失。
- 若 `pendingReboot = true`，明确告诉用户「重启后才会完全生效」，**不要谎报成功**。

### 8. 报告

固定五段：**现状 → 找到什么 → 做了什么 → 验证结果 → 没做什么（及原因）**。

## 动作分级

| Tier | 含义 | 执行要求 |
|---|---|---|
| 1 | 零风险，删了系统照跑 | 确认即可 |
| 2 | 缓存，会重建 | 说明重建代价 |
| 3 | 需判断，可能影响功能 | 逐项确认 + 展示证据 |
| 4 | 红线 | **拒绝执行**，说明原因并给人工路径 |

## 一屏体检与对比

```powershell
winmedic.ps1 probe --set intake        # 跨域只读采集（约 60-90 秒）
winmedic.ps1 summary                   # 九域一屏摘要，带 OK/WARN/BAD
winmedic.ps1 diff --from a.json --to b.json   # 两次采集对比
```

`summary` 未采集的领域显示 `[?] 未采集`，**不要据此下结论**，先补采集。

摘要末尾会直接列出「建议」（按优先级），与 `plan` 的建议段同源。要机器可读就加 `--json` 并重定向：

```powershell
winmedic.ps1 summary --json > status.json
```

## 具体软件（软件负载域）

用户点名某个软件时（LaTeX、PyCharm、Steam、Zotero、Word、代理工具……）先跑：

```powershell
winmedic.ps1 probe --set workloads
```

它按 `catalog/workloads.json` 的签名表测量各软件的**缓存**与**数据**体积，并检查代理链路一致性。

关键区分：

- `kind=cache`（着色器缓存、IDE 索引、texmf-var、OfficeFileCache）→ 可清理，代价是重建
- `kind=data`（游戏本体、Zotero 附件、微信聊天记录、texmf-dist）→ **绝不删**，只能迁移
- `kind=review`（腾讯视频下载、混合目录）→ **必须先确认**，其中可能含用户主动下载的内容
- `probe.proxy-chain` 列出 system/WinHTTP/git/npm/pip 五层代理值，`consistent=false` 就是冲突

加新软件不需要改代码：在 `catalog/workloads.json` 加一条签名（detect + measure + playbook）即可。

## 迁移决策（用户说「把缓存都搬到非 C 盘」时）

**不要一律照做。** 先跑：

```powershell
winmedic.ps1 relocate
```

它会给出磁盘概况（NVMe/SSD/HDD + 剩余空间）与每个条目的建议，分三类：

1. **已知文件夹**（文档/下载/桌面…）→ 移动文件夹一次，不要逐个软件设
   - `先搬文件夹、后装软件`：只搬文件夹即可
   - `先装软件、后搬文件夹`：**必须同时改软件内的保存路径**，否则软件指回旧路径或在原处重建空目录
   - 判定依据：该目录当前是否存在 + 软件自己记录的路径（微信 FileSavePath / Steam libraryfolders.vdf / JetBrains idea.properties）
2. **热数据**（PS 暂存盘、Premiere 媒体缓存、IDE 索引、流媒体缓存）→ **留在最快的盘**；它本来就会自动清理，搬到机械盘只会更卡
3. **冷数据**（游戏、虚拟机、书库、聊天记录）→ 搬到剩余空间最大的盘，容量优先

详见 playbook `apps-relocate-cache`（PB-913）。

## 证据查询

任何动作执行前，若用户问「为什么」「依据是什么」，直接查：

```powershell
winmedic.ps1 explain --action storage.winsxs-cleanup
```

输出含：级别、可回滚性、命令、注意事项、**证据原文与官方链接**、核对日期、验证规则。

## 风险门

`apply` 会检查恢复能力（还原点/卷影副本）：

- 目标含 **Tier 3**（不可回滚）且恢复能力不是 ready → **拒绝执行**，返回码 4
- 此时正确做法：先 `apply --action recovery.create-restore-point --yes` 建还原点，或让用户显式加 `--accept-risk`
- **不要**为了「推进任务」擅自加 `--accept-risk`

## 用户保留项（硬约束）

用户说「别动微信」「D 盘别碰」时，**立刻固化成保留项**，不要只记在脑子里：

```powershell
winmedic.ps1 profile --exclude "C:\Users\<user>\Documents\WeChat Files"
winmedic.ps1 profile --exclude "D:\*"
winmedic.ps1 profile                       # 查看当前保留项
winmedic.ps1 profile --exclude "..." --remove  # 移除
```

保留项是双层拦截：plan 阶段排除，apply 阶段再次拒绝并记账。

## 何时必须停手

- 目标是 `Windows\WinSxS` 内文件、`Windows\Installer`、`System32`、`WindowsApps`
- 目标是聊天记录目录（`WeChat Files` / `xwechat_files`）或用户声明的保留项
- 只剩 1–2 个系统还原点时要求删还原点
- 提交量已接近提交上限时要求缩页面文件
- 用户要求「全部删掉」「不用管风险」——**先解释，再只做 Tier 1/2**

## 引擎调用约定

> 若宿主只能通过 MCP 访问工具，用 `engine\mcp\winmedic-mcp.ps1`（见 [docs/MCP.md](docs/MCP.md)）；
> 工具参数与下面命令一一对应，写工具需 `yes=true`。其余规则完全一致。

- 所有子命令支持 `--json`，无 `--json` 时输出人类可读摘要。
- 退出码：0 成功 / 2 用法 / 3 权限 / 4 前置未过 / 5 plan 失效 / 6 红线 / 7 部分失败。
- **不要绕过引擎直接下删除命令**。引擎的价值就是哈希绑定、隔离区和审计日志。

## 生成报告

```powershell
winmedic.ps1 report --journal <runId>        # 五段式交付报告
winmedic.ps1 report --set storage --out report.md
```

报告固定五段：现状 → 找到什么 → 做了什么 → 验证结果 → 没做什么（及原因）。
缺数据时如实写「未采集」，不编造。

## 报告模板

```
## 现状
C: 98.7 GB，可用 16.7 GB（83%）

## 找到什么
| 项 | 大小 | 级别 | 依据 |
| 回收站 | 7.03 GB | 1 | 无影响 |
| hiberfil.sys | 6.32 GB | 1 | 微软文档：powercfg /h off |

## 做了什么
R1 回收站清空：7.03 GB -> 0
R2 关闭休眠：6.32 GB 释放

## 验证结果
C: 可用 16.7 -> 30.1 GB；待机 S0 正常；无 pendingReboot

## 没做什么
SoftwareDistribution（用户要求跳过）、Windows\Installer（高风险，建议专用工具）
```