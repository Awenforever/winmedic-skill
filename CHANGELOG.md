# Changelog

本文件格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [3.9.0] - 2026-10-25（指标治理：消灭「死案」）

### Fixed（真实缺陷，由网络排查暴露）
1. **`dx.proxy-unreachable` 是死案**：它引用的 `proxy.consistent`、`network.proxyClientCount` 在代码里**零处生产**，实跑永远是「（无数据）」
   → 新增真实指标 `network.winInetProxyEnabled` / `network.envProxySet` / `network.proxyConsistent`（由 `probe.proxy-config` 计算），重写三个假设
2. **孤儿探针**：`probe.proxy-chain` 在 catalog 里有条目但无实现 → 移除，并从诊断的 `requiredProbes` 摘掉
3. **指标名拼错**：`dx.crash-log-bloat` 引用 `cleanup.wer-reports.GB`，但目标表里是 `clean.wer` → 修正

### Added
- `catalog/metrics.json`：指标的唯一事实源，支持**静态指标**与**动态命名空间**（`cleanup.<id>.GB` 由 `cleanup-targets.json` 生成）
- `validate-catalog.ps1` 新增三方一致性校验：诊断引用的探针必须存在、指标必须注册（含动态命名空间校验）
- `tests/pester/Consistency.Tests.ps1`：3 个用例守住上述契约

### Verified
- catalog 校验通过：probes=39 actions=40 evidence=27
- Pester **267/0**，回归 **50/50**
- `diagnose --case dx.proxy-unreachable` 现在给出真实数值（0 / 0 / 1）


## [3.8.2] - 2026-10-25

### Added
- playbook **PB-503 网络链路鉴别**：五层模型（解析 → 直连 → 代理 → 长连接 → 应用连接抖动）+ 每层只读命令 + 常见根因对照 + 安全边界
- 判读要点写死：`401/403/404` 都算链路通，只有 `000` 才是断；长连接要看 `size_download` 是否完整，停滞率 >10% 足以让流式应用不断重连

### Verified（来源：ustc-wjh 上的 Codex 排查）
- 直连 000、经代理 401；30MB 下载 5 次中 1 次停在 7.7 MB；Codex 到 7897 连接数 60 秒内 4→0→3


## [3.8.1] - 2026-10-25

### Docs
- 新增病例 **0009 病程时间线被污染**：远端记录混入本机序列 + 旧测量配新时间戳，导致「一天掉 16 GB」的假象
- 病例包含完整证据链（时间线异常 → origin 分组 → generatedAt 对比）、排除项（页面文件/休眠/更新暂存/大文件）、处置与教训
- 病例库共 12 个文件


## [3.8.0] - 2026-10-25（病程数据完整性修复）

### Fixed
1. **远端记录混入本机序列**：VM 的 22.9 GB 被当成宿主机「暴跌 54 GB」→ 新增 `-Origin` 过滤，报告默认只看 `origin=local`，另加 `--origin all`
2. **记录时刻冒充测量时刻**：`trend --record` 复用 findings 却按记录时刻打点，导致 10-23 的旧测量被当成 10-25 12:00 的新样本 → 改为 `ts = findings.generatedAt`，并按 `(origin, ts, probeSet)` 去重

### Added
- `trend --rebuild`：以 findings 的测量时间为唯一依据重建序列，自动备份旧文件
- `scripts/trend-daily.ps1`：先 `probe` 再 `record`；计划任务 `WinMedicTrend` 已改为调用它
- Trend 测试新增 3 项（来源隔离、去重、老记录兼容），共 12/12

### Corrected（对 G4 结论的更正）
- 此前「宿主机一天掉 16.3 GB」是**假象**：一条 VM 记录 + 旧测量新时间戳
- 重建后的真实序列（10-23 23:05 → 10-25 17:28，1.67 天）：`volume.freeGB` 77.2 → 88.9 GB，**+11.7 GB（+6.99 GB/天）**，即空间在变多（更新清理）


## [3.7.1] - 2026-10-25

### Verified（G4 真实多日样本，终于闭环）
- 计划任务 `WinMedicTrend` 于 **2026-10-25 12:00:01 自动执行，Last Result=0**
- `trend.jsonl` 现含 **53 条快照，跨度 23.5 小时**（0.98 天）
- `trend --days 2` 首次给出真实速率：`volume.freeGB -16.674 GB/天`、`cleanup.totalGB +0.009 GB/天`
- 结论：`perDay` 计算与「跨度不足则不给速率」两项行为均已在真实跨天数据上验证

### Changed（判断层铺开）
- `PB-001 清理协议` 新增「先看『已排除』，再谈方案」：被排除 ≠ 不该动；三种原因要区分；认为排除错了要由 DSH 判断并说明
- 5 份会动手的 playbook 加指针：`storage-large-folder-management`、`apps-dev-cache-triage`、`apps-uninstall-residue`、`apps-large-app-audit`、`windows-new-device-intake`


## [3.7.0] - 2026-10-25（判断层迭代：本轮不加动作）

### Changed
- **「已排除」成为固定输出**：`plan` 的 markdown 恒有该小节（无排除项时明说「没有排除项」），并按原因分组计数 + 示例；JSON 增加 `excludedGroups`
- 意义：医生能看到「引擎忽略了什么、为什么」，而不是只看到筛选后的清单

### Added
- playbook **PB-104 缓存处置判断**：判断矩阵（该动/不该动/更该先考虑）+ 三条硬边界（不可回滚必须点名、被排除要交代、清缓存不解决变慢）
- `SKILL.md` 必做事项新增两条：读「已排除」小节、缓存决策走 PB-104

### Verified
- Plan 测试 12/12；Routing 6/6；playbooks 35
- 本机实跑：18 项因体积过小被排除，现已显式列出（含回收站等系统目标，供医生判断是否推翻）


## [3.6.1] - 2026-10-25

### Added（诊断扩容）
- 新增 3 个鉴别诊断：`dx.browser-derived-cache`（Service Worker / 着色器 / 代码缓存）、`dx.dev-cache-bloat`（pip / npm / NuGet / Gradle / HF）、`dx.crash-log-bloat`（转储 / WER / CBS 日志）
- 诊断全部基于 `cleanup.*` 指标，不输出 verdict/status，只给「指标 + 信号 + 当前值」
- Diagnose 测试 8/8

### Verified（浏览器衍生目标 6/6 / win11-test VM）
- Chrome GPU / Code、Edge GPU / Code / Dawn、Firefox startupCache：移走 + 还原 + 哈希一致
- 累计已验证 **24 / 40**


## [3.6.0] - 2026-10-25

### Fixed（元数据不实）
- `storage.hiberfil-off` 标注 `reversible=full`，但它是 `command` 型（无隔离区），`powercfg /h off` 删除的休眠文件**无法还原** → 改为 `none`
- `validate-catalog.ps1` 新增规则：`command`/`dism` 型动作声明 `reversible=full` 直接判失败

### Verified（系统类目标 4/4 / win11-test VM）
- `storage.wer-machine`、`storage.delivery-optimization`、`storage.office-file-cache`：移走 + 还原 + 哈希一致
- `storage.recycle-bin-empty`：用**构造计划**绕过 20 MB 阈值，移走 + 还原 + 哈希一致
- 累计已验证目标 **18 / 40**

### Docs
- 新增 `docs/SYSTEM-TARGETS.md`：系统类目标的边界（回收站可回滚、休眠文件与 WINSXS 不可回滚）
- `docs/VERIFIED-TARGETS.md` 更新到 18 个，并补充「构造计划」验证方法
- `storage-disk-space-recovery`、`windows-data-recovery-triage` 两个 playbook 增加「先看目标表」小节


## [3.5.3] - 2026-10-24

### Verified（10 目标批量验证 / win11-test VM）
- 一次性对 10 个目标执行 `apply → restore`：**PASS=10 FAIL=0 SKIP=0**
- 覆盖：WER、崩溃转储、npm、NuGet、Gradle、INetCache、Teams、Chrome/Edge Service Worker、系统 WebCache
- 每个目标都是「移走=True 还原=True 哈希一致=True」

### Added
- `docs/VERIFIED-TARGETS.md`：目标实测台账（已验 14 / 40，未验 26 及原因）

### Notes
- 台账的存在是为了避免「catalog 里有 = 能用」的错觉：40 个动作里目前真机闭环 14 个


## [3.5.2] - 2026-10-24

### Fixed
- **`path_absent` 校验崩溃**：新目标动作的 `verify` 只写 `kind`，而校验函数只读 `$Rule.path` → `LiteralPath 为空`。现 `Invoke-ActionVerify -Item` 传入目标、`Invoke-VerifyRule -FallbackPath` 兜底；两者皆空时返回「跳过校验」

### Added
- `trend` 快照纳入清理目标：每个目标一个 `cleanup.<id>.GB` 指标 + `cleanup.totalGB`（本机实测一次快照含 15 项）
- playbook `differential-cdisk-full` 增加「别只看系统项」小节（40 个目标分类与典型体积）
- 病例 0008：新清理目标一执行就抛 LiteralPath 为空

### Verified（多目标批量验证 / win11-test VM）
- `storage.cbs-logs`、`storage.pip-cache`、`storage.chrome-shader-cache` 三个不同目标各跑 `apply → restore`：
  **移走=True 还原=True 哈希一致=True，3/3 通过**


## [3.5.1] - 2026-10-24

### Added
- 来源守卫抽成纯函数 `Test-PlanOriginAllowed`（含 6 个用例：本地/无字段/远端拒绝/精确放行/放行不匹配/混合来源）
- 数据驱动目标探针用例 2 个（命中与未命中）
- 契约用例 2 个（`remote-apply` / `remote-restore` 缺参数 = 2）
- 三个真实病例：`0005-plan-hash-json-roundtrip`、`0006-standalone-action-blocked`、`0007-remote-quarantine-destroyed`

### Docs
- `docs/REMOTE.md` 新增「远端处置与还原」章节（用法、5 条安全不变式、实测记录）
- `docs/SAFETY-MODEL.md` 新增「远端处置的额外约束」表

### Verified
- 回归 50/50；Origins 8/8
- `Get-RemoteNewestJournal` 实测返回 `20261024-214602-9f6442`（此前 runId 提取为空的问题已修复）


## [3.5.0] - 2026-10-24

### Added（G5 达标）
- 清理目标扩到 **40 个动作**（本版 +11）：Teams、Slack、HuggingFace 模型缓存、NuGet、Gradle、Adobe 媒体缓存、Chrome/Edge Service Worker 缓存、Chrome/Edge 着色器缓存、系统 WebCache
- 新增 6 条官方证据（Teams / Slack / HF / NuGet / Gradle / Adobe），其余复用已有证据

### Verified（本机实测）
- 目录校验：probes=40 actions=**40** evidence=27
- 候选 32 项；体积 Top：Firefox 缓存 1.0 GB ×2、**Edge Service Worker 缓存 864 MB**、崩溃转储 190 MB、系统 WebCache 67 MB、pip 缓存 59 MB


## [3.4.0] - 2026-10-24

### Added（G5 覆盖扩容）
- **数据驱动的清理目标表** `catalog/cleanup-targets.json`：加目标 = 加一条数据，不再为每个目录写代码
- 新增 16 个目标 / 动作（13 → **29** 个动作）：Chrome 缓存与代码/GPU 缓存、Edge 代码/GPU/Dawn 缓存、Firefox 缓存与启动缓存、CBS 组件日志、用户与系统级 WER、用户崩溃转储、INetCache、pip 缓存、npm 缓存、传递优化缓存
- 新探针 `probe.cleanup-targets`：按表展开（含 `*` 通配与环境变量）、测量、产出候选
- 每个新动作都带 `plain` 通俗说明与 `verify`（`path_absent`），沿用不可逆确认单机制

### Verified（G5 / 本机）
- 目录校验通过：probes=40 actions=**29** evidence=21
- 本机实测命中 7 个真实目标：Firefox 缓存 ≈2.0 GB、崩溃转储 190 MB、CBS 日志 56 MB、pip 缓存 59 MB、npm 缓存 13 MB、Edge 代码缓存 6 MB 等
- `plan` 由原来的 2 项增加到 11 项

### G4 进度（趋势多日样本）
- 已在本机记录 30 条快照；`trend --days 7` 正确拒绝给出速率（间隔不足 0.5 天）
- 已创建计划任务 `WinMedicTrend`（每日 12:00 执行 `trend --record`），用于积累真实多日样本
- **多日速率验证待明日数据**，本版本不宣称已通过


## [3.3.0] - 2026-10-24

### Added
- **远端处置**：`remote-apply --target <别名> --plan <plan.json> --ids R2 --yes` 与 `remote-restore --target <别名> --journal <runId> --yes`
- 计划项级 `origin` 标记（`plan.origin` + 每个 item 的 `origin`），本地 `apply` 在**权限检查之前**即拒绝 `origin != local` 的计划（退出码 2，并提示改用 remote-apply）
- `apply --allow-remote-origin <值>`：仅允许对应该来源的计划在本机执行（远端引擎自用）
- 远端**持久状态目录** `C:\ProgramData\winmedic-remote-state`：隔离区与审计日志不随暂存目录清理
- 审计日志自动拉回本地：`state/remote-<别名>-journal-<runId>.jsonl`

### Fixed（G3 暴露）
1. **远端隔离数据会被销毁**：隔离区原本建在临时暂存目录里，暂存清理会连带删除隔离数据，远端还原不可能成功 → 改为独立持久状态目录，只清理引擎包
2. **远端引擎被自己的来源守卫拦住**：远端执行时计划 origin 恰为 `remote:<自己>`，被判定为他人计划 → 新增 `--allow-remote-origin`
3. 计划项 `origin` 为空（计算位置在 item 循环之后）→ 前移
4. 重复的来源守卫（3 份）与审计日志路径多一层 `cdrive` → 清理/修正

### Verified（G3 / win11-test VM）
- `remote --set storage` → `plan --from <远端 findings>`：plan.origin 与每个 item.origin 均为 `remote:win11-test`
- 本地 `apply --ids R2 --yes` → **拒绝**（exit 2，提示改用 remote-apply）
- `remote-apply` → **真实把 120 MB Edge 缓存移入远端持久隔离区**，目录消失，runId=20261024-214602-9f6442
- `remote-restore` → **目录恢复，3 个文件 SHA256 与原负载完全一致**
- 重复 `remote-restore` → 正确报「隔离区文件已不存在」；审计日志已拉回本地（1059 bytes）


## [3.2.1] - 2026-10-24

### Fixed
- **`apply --action`（standalone 动作）永远无法执行**：`Invoke-Apply` 在 standalone 分支之前就先要求 `plan.json` 与 `--ids`，于是唯一的 Tier 1 standalone 动作 `recovery.create-restore-point` 100% 失败——而建议层一直在推荐它。现已把 standalone 分支提到函数最前（只要求 `--yes` + 管理员），并补 `begin/done` 预写日志

### Verified（G2 / win11-test VM）
- `apply --action recovery.create-restore-point --yes` **真实成功**（67 秒，退出码 0），journal 记录 begin 21:10:03 → done 21:11:10
- `apply --action storage.winsxs-cleanup --yes` **被正确拒绝**：「该动作不是 standalone，必须通过 plan 执行」，退出码 2
- 非 standalone 动作（panther-remove）同样被拒
- `dism /Online /Cleanup-Image /AnalyzeComponentStore` 只读分析退出码 0


## [3.2.0] - 2026-10-24

### Fixed（真实处置演练暴露的 2 个致命缺陷）
1. **plan 哈希 JSON 往返不稳定**：`Get-PlanHash` 直接用 `-f` 拼接 int64，`plan.json` 回读后 size 变成 Int32，同一份计划算出不同哈希 → `apply` 一律被判「plan 校验失败」，**真实处置从未成功过**。改为规范化字符串（显式 `[int64]`/`[int]`/InvariantCulture）+ `v2` 前缀，并补「JSON 往返后哈希不变」回归用例
2. **done 记录缺 `phase`**：主循环只给 `begin` 写了 `phase`，`verify` 因此把每次成功执行都报成「中断残留」，`restore` 还会重复救回。现补 `phase='done'`，并让 `verify` 只汇总 done 记录

### Verified（G1 真实处置演练，win11-test VM / 管理员）
- 向 Edge 缓存写入 120 MB（3 个 40 MB 文件），`plan` 命中 `storage.edge-cache`
- `apply` 真实移入隔离区：**缓存目录消失**，journal 记录 begin → done（含 quarantinePath）
- `verify`：**无中断残留**
- `restore`：**3/3 文件逐字节一致**，journal 追加 restored 记录
- 演练证据保存于 `C:\ProgramData\cdrive\state\g1-evidence.jsonl`

### Notes
- 前置条件真实生效：Edge 进程运行时 `apply` 被拒（仍在运行: msedge），结束进程后才执行
- 该 VM 回收站不保留内容（删 90 MB 后 `$Recycle.Bin` 仅剩 3 个 129 字节元数据桩），所以改用目录型目标


## [3.1.2] - 2026-10-24

### Fixed
- 快照未映射 `probe.recovery-readiness` 的计数字段，导致「还原点/卷影副本」假设永远显示「无数据」；现补 `recovery.shadowCopies` / `recovery.restorePoints`
- `dx.cdisk-full` 的 h.shadow 改用 `recovery.shadowCopies`，并说明实际占用需 `vssadmin` 查询

### Verified（本机 VMware VM `win11-test`）
- 远端只读采集：`storage` 15 秒级 / `intake` 27 探针（504 s）
- 远端诊断：`diagnose --case dx.cdisk-full --from <远端 findings>` 全项有数据
- **远端沙箱自检**：`selftest` 8/8 PASS，`restore-byte-identical` 逐字节一致


## [3.1.1] - 2026-10-24

### Fixed
- **`intake` 不含 storage 探针组**：作为「首次全面体检」，它只采了 `probe.drive-space`，导致 `dx.cdisk-full` 的 8 项证据永远凑不齐。现已补上 system-files / recycle-bin / update-leftovers / package-cache / browser-cache / office-cache / app-caches（intake 探针数 20 → 27）

### Added
- `diagnose --from <findings.json>`：显式指定数据来源，便于对**远端采集结果**做诊断，而不是被动挑本地最新文件
- 契约用例：`diagnose --from` 缺文件时退出码 2

### Verified
- 本地 `probe --set intake`：27 个探针，dx.cdisk-full 所需的 8 项全部就位
- `diagnose --case dx.cdisk-full --from <远端 intake findings>`：正确报出该份数据缺哪些探针


## [3.1.0] - 2026-10-24

### Added
- **沙箱自检 `selftest`**：用真实代码路径证明可回滚
  - 造目录树 → `Invoke-QuarantineMove` 隔离 → SHA256 校验 → `Restore-JournalQuarantine` 还原 → 再校验
  - 额外覆盖「只有 begin 没有 done」的孤儿恢复
  - 8 项检查全 PASS 才返回 0；`--keep` 保留沙箱便于排查
  - 不触碰任何系统文件，可在 CI 与远端执行
- `docs/SAFETY-MODEL.md` 增加「可回滚性如何被证明」章节
- 4 个 Pester 用例 + 1 个契约用例

### Verified
- 本机实测 8/8 PASS，关键项：`restore-byte-identical`（3/3 文件逐字节一致）


## [3.0.1] - 2026-10-24

### Fixed（真实远端联调暴露的 4 个缺陷）
1. 远端命令引号语义：cmd 不剥单引号，PS 5.1 传原生参数会丢内嵌双引号 → 改为无引号无管道，新增 Format-RemotePathArg
2. 远端 TEMP 解析：cmd /c echo %TEMP% 回传带尾引号 → 清洗 + 盘符校验，失败明确报 8
3. 引导脚本变量被本地展开（ErrorActionPreference / LASTEXITCODE）→ 改单引号字面量
4. 引擎路径双反斜杠 → 单反斜杠

### Verified
- **S1 验收达成**：`remote --target win11-test --set storage`（本机 VMware VM，Windows 11 Test）成功，9 个探针全部 origin=remote:win11-test
- 远端 DESKTOP-GB7NLMT / Windows 11 Pro 26200 / 管理员，C: 62.8 GB 可用 24.2 GB；冷启动首采 152.6 s
- 远端临时目录与本地 loopback 残留已清理

### Tests
- 新增 4 个回归用例（裸路径、含空格兜底、脚本不展开变量、路径单反斜杠）

## [3.0.0] - 2026-10-24

### Added
- **病例库** `cases/`：七段式模板 + 4 个病例
  - `0001-proxy-port-drift`（代理层不一致导致 git 失败）
  - `0002-bitlocker-home-false-positive`（家庭版误报）
  - `0003-remote-executionpolicy-blocked`（远端执行策略）
  - `0000-pending-nvidia-driver-update-failed`（**待补证据**，明确标注不得当结论）
- `docs/POSITIONING.md`：主治医生模型、四层职责、超越判据、不做什么
- README 与 SKILL.md 定位改写：从「清理工具」改为「给 AI 用的诊断层」
- MCP 增加 4 个只读工具（`winmedic_remote` / `winmedic_trend` / `winmedic_diagnose` / `winmedic_tools`），共 14 个

### Notes
- 远端验收（`remote` 真实 SSH 链路）仍未完成：目标机 192.168.0.103 持续离线
- 病例原则：**没有现场证据就标 pending，不编结论**


## [2.9.0] - 2026-10-24

### Added
- **鉴别诊断**：`catalog/diagnoses.json`（`dx.cdisk-full` 7 个假设、`dx.proxy-unreachable`）与 `diagnose` 命令
  - 输出事实表：假设 × 指标 × 当前值 × 判读信号 × 数据来源；**不含 verdict/status**（有单测断言）
  - 按「对本次诊断覆盖最全」挑 findings，覆盖不足会告警并列出缺失探针
  - 趋势类检查在 `low` 置信度下只给变化量、`insufficient` 时明确无值
- **器械台**：`catalog/tools.json`（WizTree/DISM/PnPUtil/netsh/winget/ssh/scp/wevtutil）+ `tools` 命令
  - 每条登记检测方式、静默参数、Tier、可回滚性；只检测不执行
- `playbooks/differential-cdisk-full.md`（PB-915）与 `docs/DIAGNOSIS.md`
- `validate-catalog.ps1` 扩展：诊断与器械目录结构强制校验
- 10 个用例（诊断 6 + 器械 4）+ 3 个契约用例

### Fixed
- 指标访问缺陷：`[ordered]` 字典的 `.PSObject.Properties` 不返回键名，导致诊断所有指标显示「无数据」；改为 `Test-TrendMetric` / `Get-TrendMetricValue` 统一访问


## [2.8.0] - 2026-10-24

### Added
- **病程层**：`trend --record` 把每次采集压成一条快照，只追加到 `state/trend.jsonl`；`trend` 读时间序列给出变化与速率
- 快照指标：卷剩余、休眠文件、回收站、浏览器缓存、Office 缓存、应用缓存、软件负载缓存合计
- **置信度规则**：样本 <2 → `insufficient`（不排序不给速率）；间隔 <0.5 天 → `low`（只给变化量）；否则 `ok`（给每日速率）
- `docs/TREND.md`：数据格式、置信度规则、计划任务配置示例
- 9 个用例（快照 2、增长 4、记录与报告 3）+ 2 个契约用例

### Notes
- 刻意的取舍：短间隔抖动不算趋势，宁可说「样本不足」也不外推
- 目录级增长仍依赖 WizTree 导出，当前到「域级/软件级」


## [2.7.0] - 2026-10-24

### Added
- **远程会话层**：`remote --target <别名> --set <探针集>`，SSH 只读采集并回传
  - 打包最小运行集 → scp → 远端临时目录 → 跑 probe → 回传 → 落库 → 默认清理
  - 回传 findings 一律打 `origin=remote:<别名>`，本地 apply 拒绝远端条目
  - `--via local` loopback 模式（CI 与本机自测）
- 新退出码 `8 = REMOTE`（远端不可达/传输失败）
- `docs/REMOTE.md`：用法、安全边界、失败处理、已知限制
- 9 个用例（target 解析 4 + origin 2 + 命名/脚本 2 + loopback 端到端 1）+ 3 个契约用例

### Notes
- 只用既有 SSH 信任，`BatchMode=yes` 杜绝交互式密码；不写入任何凭据
- **SSH 传输路径尚未在真实远端验证**：编写时目标机（192.168.0.103）离线。loopback 链路已验证


## [2.6.0] - 2026-10-24

### Added
- **不可逆操作确认单**：`apply --purge` 执行前打印逐项说明，每项固定六行——这是什么 / 在哪里 / 有多大 / 为什么可以删 / 删了会怎样 / 能不能撤回
- **确认单令牌子** `--confirm-token`：令牌为 `sha256('purge|计划指纹|条目列表')` 前 8 位；换条目或换计划即失效，未回填或填错则不执行（退出码 2，不删除任何内容）
- `catalog/actions.json` 的 13 个动作全部补齐 `plain`（what / why / consequence），针对具体后果手写，非模板套话
- `validate-catalog.ps1` 强制校验：动作缺 `plain` 或字段不全时 CI 失败
- `engine/lib/Explain.ps1`：`Get-PlainExplanation` / `New-PurgeConfirmationToken` / `Format-PurgeConfirmation`

### Notes
- 兜底文案是「catalog 未提供通俗说明，按不可逆处理」，而不是编造解释——说明不了后果就不该删
- 与 v2.5.0 的双闸串联：`--purge` 需要 `--accept-irreversible`（声明知情）+ `--confirm-token`（证明看过单子）

### Tests
- 新增 8 个用例（通俗说明 2 + 确认单内容 4 + 令牌绑定 2），总计 211 Pester + 6 路由

## [2.5.0] - 2026-10-24

### Changed
- 把「**只能帮用户变得更好，不能造成不可逆损害**」写为最高约束（docs/SAFETY-MODEL.md），**不提供任何绕过开关**

### Added
- **预写日志（WAL）**：动作执行前写 `phase=begin`，完成后写 `phase=done`；解决「移动到一半进程被杀 → 隔离区有文件但无记录」的恢复盲区
- `Get-JournalOrphans`：识别「有 begin 无 done」的中断项，并判断隔离区是否真有内容
- `verify` 显示中断残留并提示可 `restore` 救回；`restore` 支持救回孤儿项（内容不唯一时拒绝并转人工）
- `--purge` 双闸：必须同时 `--accept-irreversible` 才是显式确认物理删除（`Test-PurgeAllowed`）
- 引擎自身状态/隔离目录加入红线（`Test-StateDirPath`）

### Tests
- 新增 8 个护栏用例（双闸 3 + 状态目录 2 + 中断恢复 3），总计 203 Pester + 6 路由

## [2.4.0] - 2026-10-24

### Changed（架构）
- **职责重新划分**：引擎只提供**事实**与**护栏**，迁移方案由 Agent 判断，不再由引擎内置规则下结论
- `relocate` 输出改为三段：**决策清单（必须逐条回答）→ 事实表 → 默认建议**
- 默认建议统一标注 `policySource=default-hint`，明示「可被判断推翻，不许当结论转述」
- `playbook apps-relocate-cache` 从「规则表」重写为「决策程序」（三个必答问题 + 方案格式 + 红线）
- SKILL.md 增加**强制决策协议**：回答里必须覆盖三条清单问题，否则算违规

### Added
- `Get-RelocationFacts`：纯事实层（路径/介质/是否存在/已知文件夹/软件声明路径），不含 action 结论
- `Get-RelocationChecklist`：三条固定问题，覆盖已知文件夹、热/冷数据、先装后搬三个误判点
- SKILL.md 触发词补充：把缓存搬到 D 盘 / C 盘装不下 / 新软件装哪个盘 / 微信文件太大 / 暂存盘

### Tests
- 新增 4 个用例（清单固定三条、事实层不含结论、识别已知文件夹、默认建议标注），迁移相关共 12 个；总计 195 Pester + 6 路由

## [2.3.0] - 2026-10-24

### Added
- **迁移策略层** `engine/lib/Relocation.ps1`：按「盘介质 + 已知文件夹 + 热/冷数据」给出迁移建议，而不是一律搬出 C 盘
- `winmedic relocate` 命令与 `probe --set relocation`
- 盘介质探测（NVMe / SSD / HDD + 剩余空间），已知文件夹当前路径探测
- 软件自有路径读取（微信 `FileSavePath`、Steam `libraryfolders.vdf`、JetBrains `idea.properties`）作为时序判据的硬证据
- 签名表支持引用已知文件夹实际位置（`{kfDocuments}` 等），不再写死 `%USERPROFILE%\Documents`
- 新增签名：VMware、Adobe Premiere、Adobe Photoshop；微信改为按「文档」下的真实目录测量
- 2 个 playbook：`apps-relocate-cache`（决策模型）、`apps-adobe-triage`（暂存盘/媒体缓存）

### Fixed
- **迁移建议的时序错误**（用户指出）：此前把「移动已知文件夹」当成通用解法，忽略了「先装后搬」场景下软件配置里已存绝对路径。现区分为 `known-folder`（先搬后装）与 `known-folder-then-app`（先装后搬，必须同步改软件设置），并用目录是否存在 + 软件声明路径判定
- `Get-RelocationAdvice` 的 policy 兜底：policy 为空时按 kind 推导（函数自洽，不依赖调用方）

### Notes
- 本机实测：C: NVMe 237GB、D:/F: SATA SSD、E: HDD 1863GB；已知文件夹已在 E:，因此微信等软件的数据自然落在 `E:\__VIVE__\Documents`，验证了「先搬后装」路径

### Tests
- 新增 8 个迁移用例（时序 3 + 热冷判据 5），总计 191 个 Pester + 6 个路由用例

## [2.2.0] - 2026-10-24

### Added
- 签名表从 5 条扩到 **14 条**：新增腾讯视频、微信、腾讯会议、OneDrive、网易云音乐、npm/pnpm 开发缓存、Calibre、OBS、Adobe
- 新增 `kind=review`（需人工确认）：单独累计为 `reviewBytes`，不计入 cache/data，避免把「用户主动下载的视频」当缓存
- 2 个 playbook：`apps-sync-clients-triage`（同步盘/会议/播放器）、`apps-dev-cache-triage`（npm/pnpm/构建产物）
- 建议规则：review 类 ≥1 GB 提示「需人工确认」

### Notes
- 本机实测（14 签名全部命中，2.3 秒）：OneDrive 缓存 1.13 GB、腾讯会议 913 MB、TeX 323 MB、网易云 156 MB、Steam 缓存 143 MB、Office 125 MB；另有三类不计入清理：腾讯视频 2.18 GB（review）、微信 2.98 GB（data）、Steam 游戏库 225 GB（data，在 D 盘）

### Tests
- 新增 2 个用例（review 累计、review 建议），总计 183 个 Pester + 6 个路由用例

## [2.1.0] - 2026-10-24

### Added
- **软件负载域**：`probe --set workloads`，按签名表测量具体软件的缓存/数据体积
- `catalog/workloads.json`：TeX Live / JetBrains / Steam / Zotero / Office-Word 五条签名，含 detect 规则（注册表 / PATH 命令 / 固定路径）与 measure 规则（cache / data / config）
- `probe.proxy-chain`：比对 system / WinHTTP / git / npm / pip 五层代理，列出本机已装的代理与加速器客户端
- 6 个 playbook：LaTeX、JetBrains IDE、Steam、Zotero、Word、代理链路一致性
- `validate-catalog.ps1` 增加 workloads 校验：id 唯一、playbook 存在、kind 合法、占位符必须已声明
- 建议规则：软件缓存 ≥1 GB（取前 3）、Steam 库 ≥100 GB、Zotero 数据 ≥5 GB、代理链路不一致

### Notes
- 实测本机：TeX 缓存 323 MB、Steam 游戏库 225.76 GB（在 D 盘）、JetBrains 配置 865 MB、Office 缓存 125 MB、已装 8 个代理/加速器客户端

### Tests
- 新增 12 个负载用例 + 3 个建议用例，总计 180 个 Pester + 6 个路由用例；回归 38 项

## [2.0.0] - 2026-10-24

### Added
- **MCP 服务器** `engine/mcp/winmedic-mcp.ps1`：stdio JSON-RPC 2.0，10 个工具，PowerShell 5.1 实现零依赖
  - 写工具（apply/restore）必须显式 `yes=true`；`-ReadOnly` 可整体禁用
  - 完全继承引擎红线、风险门、plan 哈希与审计日志，服务器本身不拼命令
- `docs/MCP.md`：协议细节、客户端配置示例、安全边界与已知限制
- 7 个 MCP 集成用例（真实启动子进程、喂 stdin、解析 stdout）

### Changed
- 版本进入 2.x：能力面从「CLI + Skill」扩展到「CLI + Skill + MCP」


## [1.17.0] - 2026-10-24

### Added
- 邮件域（只读）：`probe --set mail`，覆盖第 10 个领域
- `probe.mail-clients`：Outlook 是否安装/版本、配置文件与默认配置、OST/PST 列表与体积、加载项状态（含 LoadBehavior 语义）、新版 Outlook 检测
- 纯函数 `Get-OstSizeVerdict`（empty/small/normal/large/oversize）与 `Get-AddinLoadVerdict`（0/1/2/3/8/9/16 语义）
- 建议规则：数据文件 ≥25 GB 或存在未加载/已禁用加载项 → `rec.mail-outlook`
- playbook：`outlook-troubleshooting`、`mail-connectivity-triage`

### Notes
- 邮件域不做网络测试，端口与连通性仍由宿主 Agent 用 `Test-NetConnection` 显式执行（保持引擎不联网不变量）

### Tests
- 新增 9 个用例（邮件 7 + 建议 2），总计 158 个 Pester + 6 个路由用例

## [1.16.0] - 2026-10-24

### Added
- `summary` 末尾直接列出处置建议（按优先级），与 `plan` 建议段同源；不再需要先跑一遍 plan 才知道该做什么
- `summary --json` 输出 `host / probeSet / domains / recommendations` 结构化结果，可直接被外部程序消费

### Fixed
- **`--json` 输出一直为空**：派发器用 `$code = Invoke-Xxx` 捕获函数返回值，把函数内 `Write-Output` 的 JSON 一并吞进变量，从未到达控制台。改为 `[Console]::Out.WriteLine` 直写 stdout（随修随验：`summary --json > x.json` 得到 9 域 4 建议）
- `--json` / `--accept-risk` 等布尔开关写在双横线形式时被当成未知参数；现单独识别且不吞掉后续 token

### Tests
- 新增 2 个摘要建议用例；回归新增 1 项「JSON 契约」（重定向解析）共 36 项


## [1.15.0] - 2026-10-24

### Added
- **建议层** `engine/lib/Recommendations.ps1`：把只读探针结论翻译成跨域处置建议（10 条确定性规则）
- `plan.json` 新增 `recommendations` 字段；`plan.md` 新增「建议（按优先级）」段，标注「可执行 / 人工 playbook」
- `report` 第 2 段附带处置建议表
- 建议来源全部可回答：每条绑定探针结论 + playbook 或 catalog 证据

### Fixed
- `int + string` 拼接在 PowerShell 中走数值转换导致建议生成抛异常（被 try/catch 吞掉后表现为「无建议」）；改为字符串前置拼接

### Tests
- 新增 14 个建议用例 + 2 个方案断言，总计 145 个 Pester + 6 个路由用例；CLI 契约增至 31 项，回归 35 项


## [1.14.0] - 2026-10-24

### Added
- 英文文档：`README.en.md`、`docs/en/QUICKSTART.md`、`docs/en/README.md`（含中英术语对照）
- `SKILL.md` 的 `whenToUse` 增加英文关键词，英文请求也能正确路由
- 回归新增「直接调用」用例组（6 项）：专测 `--set` / `--ids` 等双横线写法，共 34 项
- `docs/FIELD-NOTES.md` 增加机器 E（Augenstern）真机回归记录

### Fixed
- **双横线参数在直接调用时失效**：`[Parameter(Position=1)]` 让 `SubCommand` 抢先吃掉 `--set`；现改为不占位，并新增 `Resolve-RestArguments` 归一化 `--xxx` 与 `--accept-risk`（真机回归发现）
- **家庭版 BitLocker 误报**：新增 `Test-BitLockerSupported`，Home/家庭版不再判为「未保护」（真机回归发现）


## [1.13.0] - 2026-10-24

### Added
- `summary`：九域一屏体检（磁盘/启动/应用/更新/网络/安全/恢复/备份/外设），带 OK/WARN/BAD/未采集 标记
- `diff --from --to`：两次采集的指标对比（可用空间、启动项、待重启、问题设备、打印机问题、疑似残留、安全/恢复/备份等级）
- `Get-SummaryLines` / `Get-DiffMetrics` 为纯函数，可单测

### Fixed
- `summary`/`report`/`plan` 曾固定读 `storage-findings.json`；现改为：显式 `--set` 用指定文件，否则取**最新一次采集**
- 待重启现在会拉低「更新」域判定（此前仍显示 OK）

### Tests
- 新增 8 个用例（摘要行 5 + 渲染 1 + 对比 2），总计 127 个 Pester + 6 个路由用例；CLI 契约增至 24 项


## [1.12.0] - 2026-10-24

### Added
- `explain [--action <id>]`：列出全部动作，或展示单条动作的完整依据（级别/可回滚/命令/注意事项/证据原文与链接/核对日期/验证规则）
- **风险门** `Test-RiskGate`：目标含 Tier 3 且恢复能力非 ready 时拒绝执行（码 4），可用 `--accept-risk` 显式承担；Tier 4 永远拒绝
- `recovery.create-restore-point`：唯一可 `--action` 单独执行的动作（Tier 1、加性、需管理员），配套 `restore_point_exists` 验证规则与官方证据

### Tests
- 新增 7 个单元用例（风险门 6 + 还原点验证 1）与 5 个 CLI 契约用例，回归共 25 项


## [1.11.0] - 2026-10-24

### Changed
- 把 `restore` 的移动逻辑从派发器抽成 `Restore-JournalQuarantine`（Journal.ps1），使其可单测、可复用；派发器只负责编排与记账

### Tests
- 新增 4 个隔离区往返用例：移动→恢复、原位置冲突拒绝、隔离区文件丢失、同名冲突自动加后缀
- 这补上了此前「apply→restore 因需管理员而未在 CLI 层覆盖」的缺口


## [1.10.0] - 2026-10-24

### Added
- `scripts/regress.ps1` 回归脚本：静态解析 → catalog 校验 → 单元测试 → **CLI 契约与安全负向测试**（退出码断言 + 输出卫生）
- CI 增加 `CLI contract regression` 步骤（跳过单元测试以免重复）

### Fixed
- `plan` 在 `probe` 改用 `<set>-findings.json` 后仍只找 `findings.json`，导致找不到采集结果（回归首轮抓到）
- 上一版 H14 补丁误删 `$rec = @{`，导致 `winmedic.ps1` 语法错误、所有子命令 exit 1（回归第二轮抓到）
- `apply` 缺 `--ids` 时先撞权限检查返回 3；改为**参数校验先于权限校验**，返回 2

### Notes
- 这三处都是回归脚本上线后立刻抓到的真实缺陷，其中一处会让整个 CLI 无法启动——说明 CLI 层断言不可省


## [1.9.0] - 2026-10-24

### Added
- 前置检查 `commit-headroom:N`：提交余量不足 N% 时拦截（对应难例 H4）

### Changed
- 幂等：隔离类动作在目标已不存在时返回 `mode=absent` 并记为 `skipped`，不再计为失败（对应难例 H14）
- 顺序修正：**策略检查优先于状态检查** —— 跨卷目标一律拒绝，即使该目标已不存在

### Tests
- 新增 6 个用例（Safety 2 + Action 4），总计 108 个 Pester + 6 个路由用例
- 覆盖：提交余量、跨卷拒绝、目标已消失、命令成功/失败退出码


## [1.8.0] - 2026-10-24

### Added
- 备份域（只读）：`probe --set backup`
- `probe.backup-status`：文件历史记录、OneDrive 文件夹备份、系统映像、还原点、卷影副本
- `Get-BackupVerdict`：none / weak / ok —— 只有系统级恢复手段不算「有备份」
- playbook：`setup-backup`（3-2-1 原则 + 恢复验证）

### Notes
- 混淆「系统还原点」与「数据备份」是最常见的认知错误，playbook 与裁决逻辑都显式区分

### Tests
- 新增 6 个用例，总计 102 个 Pester + 6 个路由用例


## [1.7.0] - 2026-10-24

### Added
- 打印机域（只读）：`probe --set printers`
- `probe.printers`：打印机清单、默认打印机、Spooler 状态、队列任务、问题计数
- `Get-PrinterWorkOfflineVerdict`：把脱机/卡纸/缺纸/耗材/暂停/报错翻成人话（判定顺序：卡纸 > 缺纸 > 耗材 > 暂停 > 脱机 > 报错）
- playbook：`printer-repair`

### Fixed
- 分类顺序问题：`Paper Jam` 曾被 `paper` 规则先命中而误判为「缺纸」

### Tests
- 新增 6 个用例，总计 96 个 Pester + 6 个路由用例


## [1.6.0] - 2026-10-24

### Added
- `report` 子命令：把 findings / plan / journal 合成五段式交付报告（现状 → 找到什么 → 做了什么 → 验证结果 → 没做什么）
- 自动挑选最近一次 findings 与 journal（也可用 `--set` / `--journal` 指定），`--out` 指定输出路径
- 未取证的探针、跳过的项、排除项都会如实列出；体积过小的排除项收敛为一行汇总

### Tests
- 新增 6 个报告用例，总计 90 个 Pester + 6 个路由用例


## [1.5.0] - 2026-10-23

### Added
- 恢复分诊域（只读）：`probe --set recovery`
- `probe.restore-points` / `probe.shadow-copies` / `probe.winre` / `probe.recovery-readiness`
- 恢复能力总评 ready / weak / poor：没有还原点、没有卷影副本、WinRE 未启用时逐项计风险
- playbook：`windows-data-recovery-triage`、`boot-failure-triage`

### Notes
- 实测本机结论为 `poor`（无还原点、无卷影副本）——正是长期清理的典型后遗症，可作为清理前的安全提醒

### Tests
- 新增 6 个用例，总计 84 个 Pester + 6 个路由用例


## [1.4.0] - 2026-10-23

### Added
- 安全态势域（只读，不修改任何安全配置）：`probe --set security`
- `probe.defender`（实时保护/病毒库天数/篡改防护/排除项计数）、`probe.firewall`、`probe.bitlocker`、`probe.hardening`（SMB1/安全启动/管理员组/Guest）、`probe.security-posture`（总体裁决）
- 纯函数 `Get-SignatureAgeDays` / `Get-SecurityVerdict`：未知项按「无法读取」处理，不误判为不安全
- playbook：`endpoint-security-check`、`bitlocker-recovery-triage`

### Tests
- 新增 9 个用例，总计 78 个 Pester + 6 个路由用例


## [1.3.0] - 2026-10-23

### Added
- 网络域（只读配置，**不发起网络请求**）：`probe --set network`
- `probe.network-adapters` / `probe.dns-config` / `probe.proxy-config` / `probe.vpn-adapters`
- `Get-ProxyConflictSummary`：比对 WinINET / WinHTTP / 环境变量三处代理，检出不一致（实测踩过的 7890 vs 13499 坑）
- `Test-IsVpnAdapterName`：识别 VPN / 隧道 / 虚拟化网卡
- playbook：`network-diagnostics`、`vpn-proxy-troubleshooting`

### Design decisions
- 连通性测试（ping / Test-NetConnection）**不进引擎**，由宿主 Agent 显式执行，以维持「引擎不联网、无遥测」的不变量。

### Tests
- 新增 11 个用例，总计 69 个 Pester + 6 个路由用例


## [1.2.0] - 2026-10-23

### Added
- 更新/驱动/设备域（只读）：`probe --set updates`
- `probe.windows-update`：待重启判定（CBS / WU / PendingFileRename）、更新相关服务状态、近期补丁、失败事件（ID 20/25/31）
- `probe.drivers`：问题设备枚举（ConfigManagerErrorCode）+ 中文解释 + 显卡驱动版本
- playbook：`update-troubleshooting`、`windows-driver-device-triage`
- `Get-DeviceErrorMeaning` / `Get-PendingRebootState` 纯函数，便于单测

### Tests
- 新增 9 个用例，总计 58 个 Pester + 6 个路由用例


## [1.1.0] - 2026-10-23

### Added
- `profile` 子命令：`--exclude` 固化用户保留项，`--remove` 移除，无参数查看；profile 落盘到 `%ProgramData%\cdrive\profile.json`
- 保留项双层拦截：plan 阶段进入 `excluded`，apply 阶段再次拒绝并写 journal（`reason=user-exclude`）
- 通配符匹配（`*` / `?`），大小写不敏感，前缀路径自动包含子路径

### Tests
- 新增 11 个用例（匹配 7 + 持久化 3 + 方案拦截 1），总计 49 个 Pester 用例


## [1.0.0] - 2026-10-23

### Added
- 应用域（只读审计）：`probe --set apps`
- `probe.installed-apps`：三个卸载注册表分支枚举 + 去重 + 识别「注册表指向的目录已不存在」
- `probe.app-dirs`：ProgramData / LocalAppData\Programs / LocalAppData 的大目录扫描（带时间预算与截断标记）
- `probe.app-residue`：疑似遗留目录 + 失效注册表条目，**只举证不删除**
- 名称相似度 `Test-NameSimilar`：归一化包含 + 词元重叠 + 共同前缀，宁漏勿错

### Design decisions
- **应用域不提供自动删除残留的动作**。目录名与程序名的匹配天然存在误判（实测中 `day-pc` 这类用户自建目录会被列为嫌疑），自动删除的期望收益远低于误删代价。
- 扫描带 90 秒时间预算，超时标记 `truncated`，不静默截断。

### Tests
- 新增 12 个应用域用例（归一化 3 + 相似度 4 + 残留识别 4 + 探针 1），总计 38 个 Pester 用例


## [0.5.0] - 2026-10-23

### Added
- 启动/性能域（只读诊断）：`probe --set boot` 与 `probe --set intake`
- 探针：启动耗时事件（Diagnostics-Performance 100/101/102/103）、启动项枚举（Run/RunOnce/启动文件夹）、性能基线（内存/提交/进程/磁盘队列）、磁盘健康、自动服务计数
- 启动项分类器 `Get-StartupRiskCategory`：security / system / input / driver / updater / sync / vendor / unknown，并给出 keep / optional-disable / investigate 建议
- `probe --set all` 聚合存储 + 启动

### Changed
- `probe` 输出文件名按探针集区分（`<set>-findings.json`），避免互相覆盖
- 探针失败不再整体报错，改为逐项标记 `ok=false` 并在输出中列出

### Tests
- 新增 13 个启动域用例（分类器 8 + 探针 5），总计 26 个 Pester 用例


## [0.1.0] - 2026-10-23

### Added
- 仓库骨架：LICENSE(MIT)、VERSION、CI、catalog schema 校验、`gh-setup.ps1`
- 引擎骨架 `engine/winmedic.ps1`：`doctor` / `probe` / `plan` / `apply` / `verify` / `restore` / `journal`
- 公共层 `engine/lib/Common.ps1`：退出码、编码、权限、哈希、系统文件存在性判定
- 存储域探针 `engine/probes/storage.ps1`：WizTree 导出与索引、降级定向测量
- catalog：probes / actions / evidence 三张表的初始定义
- `playbook-index.md` 与 storage 域 playbook 骨架

### Notes
- 目标运行时为 Windows PowerShell 5.1（不依赖 pwsh 7）
- 所有破坏性动作默认进入隔离区，支持 `restore` 回滚
