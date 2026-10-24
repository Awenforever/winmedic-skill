# Changelog

本文件格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

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
