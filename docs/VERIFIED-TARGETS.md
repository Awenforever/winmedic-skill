# 目标实测台账

> 只有真机跑过 `apply → restore` 且**字节一致**的目标才算「已验证」。

## 已验证（14 个 / 40）

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

## 未验证（26 个）

其余动作仅在 catalog 中存在，未做真机闭环。其中：

- 浏览器类（Edge/Chrome 缓存与 GPU/Dawn 缓存）：与已验证的同类路径同构，风险低但未逐一跑
- 系统类（系统级 WER、传递优化、Office 缓存、回收站、休眠文件）：涉及共享状态或系统文件，需单独设计用例
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
