# WinMedic

> **DSH Agent 的 Skill：给 AI 用的「主治医生」，不是给用户双击的清理软件。**

传统电脑管家只能清缓存、小打小闹。WinMedic 要解决的是那些**没有现成软件能处理**的事：

| 场景 | 传统软件 | WinMedic |
|---|---|---|
| C 盘满了 | 清缓存，清了还满 | 做鉴别诊断：休眠/还原点/组件膨胀/某个目录在暴涨 |
| 远端 PC 驱动更新失败 | 无解 | 远程采集 → 事件日志/安装日志 → 假设排除 |
| git 能用、浏览器能用，但 push 失败 | 无解 | 五层代理对照，找出「某层还指着旧端口」 |
| 缓存该不该搬到别的盘 | 建议全搬 | 先判热/冷、先装后搬、已知文件夹 |

原则：**引擎只给事实，判断归 Agent；红线绝不放开，不制造不可逆损害。**

详见 [docs/POSITIONING.md](docs/POSITIONING.md)。

> 发布前必读：[已知局限](docs/KNOWN-LIMITATIONS.md)

## 安装 / 升级 / 卸载

```powershell
# 安装（默认 %LOCALAPPDATA%\Programs\WinMedic，无需管理员）
Expand-Archive .\winmedic-skill-1.0.0.zip -DestinationPath .
powershell -ExecutionPolicy Bypass -File .\install.ps1

# 使用入口
winmedic.cmd doctor
winmedic.cmd probe --set storage

# 升级（覆盖安装，状态目录保留）
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Force

# 卸载（默认保留隔离区与审计日志）
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

> 安全软件若拦截 `engine/lib/Remote.ps1`，安装会**降级并提示**：远端功能不可用，其余正常。
> 处理方式见 [已知局限](docs/KNOWN-LIMITATIONS.md)。

## 四件结构性能力

| 能力 | 命令 | 说明 |
|---|---|---|
| 远程能到 | `remote` | SSH 只读采集，结果打 `origin` 标记 |
| 病程能看 | `trend` | 只追加时间序列；样本不足就明说 |
| 病因能排 | `diagnose` | 假设×指标×信号表，**不给结论** |
| 经验能留 | `cases/` | 七段式病例，可复现可交接 |

## 快速开始

```powershell
.\engine\winmedic.ps1 doctor            # 环境自检
.\engine\winmedic.ps1 probe --set intake # 只读采集
.\engine\winmedic.ps1 summary            # 九域摘要 + 处置建议
.\engine\winmedic.ps1 diagnose --case dx.cdisk-full
```

## 已有能力（节选）

- 40 个探针、**40 个处置动作**（数据驱动目标表）、34 个 playbook
- 隔离区 + 预写日志（WAL）+ 孤儿恢复；`--purge` 需双确认 + 确认单令牌
- 迁移决策：区分热/冷数据、已知文件夹、先装后搬
- MCP 服务器（14 个工具），供不支持跑脚本的宿主使用



## 具体软件覆盖（软件负载域）

不是每个软件都写一套代码，而是一张**签名表**（`catalog/workloads.json`）：

| 软件 | 缓存（可清） | 数据（不可删） |
|---|---|---|
| TeX Live | `texmf-var`（字体/luatex 缓存） | `texmf-dist` 发行版本体 |
| JetBrains IDE | `caches` / `index` / `log` | `%APPDATA%\JetBrains` 配置与插件 |
| Steam | `shadercache` / `appcache` / `depotcache` | `steamapps\common` 游戏本体 |
| Zotero | — | `storage` 附件、`zotero.sqlite` |
| Office / Word | `OfficeFileCache` | `Normal.dotm` 模板 |
| 腾讯会议 / 网易云 / OneDrive | 日志、ListSync、流媒体缓存、更新包 | `settings`、登录态 |
| npm / pnpm | npm-cache、pnpm store | — |
| 腾讯视频 | — | **需人工确认**（可能含已下载视频） |
| 微信 | — | 聊天记录（只能迁移） |
| Calibre / OBS / Adobe | Adobe 媒体缓存 | 书库、场景配置、推流密钥 |

另有 `probe.proxy-chain`：比对 system / WinHTTP / git / npm / pip 五层代理，检出「关了代理反而全断」的根因。

**加新软件 = 加一条签名**，不用改探针代码。

## MCP（可选）

宿主不方便直接跑脚本时，可用内置 MCP 服务器（stdio JSON-RPC，PowerShell 实现，零依赖）：

```powershell
.\engine\mcp\winmedic-mcp.ps1              # 全功能
.\engine\mcp\winmedic-mcp.ps1 -ReadOnly    # 只读审查模式
```

10 个工具（doctor / probe / summary / plan / apply / verify / restore / journal / explain / profile），
写工具必须显式 `yes=true`，且完全继承引擎的红线、风险门与 plan 校验。详见 [docs/MCP.md](docs/MCP.md)。

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
| v1.2 | + 更新/驱动/设备 | 15 | ✅ 已发布 |
| v1.3 | + 网络 | 17 | ✅ 已发布 |
| v1.4 | + 安全态势 | 19 | ✅ 已发布 |
| v1.5 | + 恢复分诊 | 21 | ✅ 已发布 |
| v2.0 | + 新机验收/基线 | 35+ |

当前状态见 [CHANGELOG.md](CHANGELOG.md) 与 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 许可证

[MIT](LICENSE)
