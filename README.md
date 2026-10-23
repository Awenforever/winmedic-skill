# WinMedic

> Windows 电脑维修 Skill —— 诊断、清理、迁移、修复。**只读优先、可回滚、带证据链。**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

WinMedic 是一个给 AI Agent 用的 Windows 维修技能包。它把「判断」交给模型，把「执行」交给一个零依赖的确定性引擎。

## 和别的清理/维修 Skill 有什么不同

| | 常见做法 | WinMedic |
|---|---|---|
| 执行 | Playbook 描述「语义工具」，由 Agent 现场拼命令 | 引擎提供固定动作，**Agent 只传 id，不拼命令** |
| 回滚 | 提示「请先确认」 | **Quarantine 软删除 + Journal + restore**，默认可撤销 |
| 证据 | 讲道理 | 每条建议强制携带 **官方链接 + 原文 + 实测日期**，CI 校验 |
| 测试 | 无 | Pester 单测 + 14 个引擎难例 + 6 个路由难例 |

一句话：**它教你怎么修；WinMedic 保证修得对、错了能退、并且能证明为什么这么修。**

## 快速开始

```powershell
# 1. 环境自检（只读）
.\engine\winmedic.ps1 doctor

# 2. 采集（只读）——缺 WizTree 会自动降级
.\engine\winmedic.ps1 probe --set storage

# 3. 生成方案（只读）
.\engine\winmedic.ps1 plan --from .\state\findings.json

# 4. 执行（需要显式 --yes；默认进隔离区，不直接删）
.\engine\winmedic.ps1 apply --plan .\state\plan.json --ids R1,R2 --yes

# 5. 复核 / 回滚
.\engine\winmedic.ps1 verify --journal 20261023-215500
.\engine\winmedic.ps1 restore --journal 20261023-215500
```

## 安全模型

- **只读优先**：`doctor` / `probe` / `plan` / `verify` 全部只读，`apply` 是唯一写入口。
- **plan 哈希绑定**：执行时重算 plan 哈希，被改动过就拒绝。
- **Quarantine 软删除**：默认移动到 `%ProgramData%\winmedic\quarantine\`，同盘移动是毫秒级元数据操作；只有 `--purge` 才真删。
- **红线硬拒**：Tier 4 目标（WinSxS 子目录、Windows\Installer、System32、聊天记录等）由引擎直接拒绝，不依赖提示词。
- **权限降级**：非管理员只能只读，`apply` 直接退出码 3。

详细语义见 [docs/SAFETY-MODEL.md](docs/SAFETY-MODEL.md)。

## 目录结构

```
SKILL.md                路由与强制工作流（给 Agent 读）
playbook-index.md       症状 → playbook 的路由表
playbooks/*.md          各领域判断流程（懒加载）
engine/                 确定性引擎（PowerShell 5.1，零依赖）
catalog/                探针 / 动作 / 证据的机器可读定义
tests/                  Pester 单测、路由测试、fixtures、真机 lab
docs/                   设计、安全模型、证据契约、难例、路线图
```

## 要求

- Windows 10 / 11
- **Windows PowerShell 5.1**（系统自带，无需安装 pwsh 7）
- 可选：WizTree（有则快，无则降级为定向测量）

## 路线图

| 版本 | 领域 | playbook |
|---|---|---|
| v0.1 | 平台 + 存储 | 4 | ✅ 已发布 |
| v0.5 | + 启动/性能 | 7 | ✅ 已发布 |
| **v1.0** | + 应用生命周期 | **11** | ✅ 已发布 |
| v1.1 | + 更新/驱动/设备 | 15 |
| v1.2 | + 网络 | 20 |
| v1.3 | + 安全态势 | 25 |
| v1.4 | + 恢复分诊 | 30 |
| v2.0 | + 新机验收/基线 | 35+ |

当前状态见 [CHANGELOG.md](CHANGELOG.md) 与 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 许可证

[MIT](LICENSE)
