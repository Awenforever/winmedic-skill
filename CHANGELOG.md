# Changelog

本文件格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

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
