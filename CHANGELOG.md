# Changelog

本文件格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

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
