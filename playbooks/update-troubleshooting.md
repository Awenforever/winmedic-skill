# Windows 更新故障

## 适用
「更新一直失败」「卡在 0%」「更新完又回滚」「重启后又说要更新」。

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set updates
```

看 `probe.windows-update`：
- `pendingReboot.pending` 为真 → **先重启**，很多「失败」其实是没重启
- `services`：wuauserv / BITS / TrustedInstaller / DoSvc 是否被停用
- `recentFailures`：错误时间与首行错误码
- `recentHotfixes`：最近装了什么

## Step 2: 按错误码分流

| 迹象 | 常见原因 | 处理 |
|---|---|---|
| 0x80070005 | 权限/安全软件拦截 | 确认安全软件策略，不要盲关 |
| 0x800f081f | 组件存储损坏 | DISM /RestoreHealth 后重试 |
| 0x80070643 | .NET 运行时安装失败 | 单独修 .NET，不走累积更新 |
| 反复回滚 | 驱动或第三方内核组件冲突 | 查最近安装的驱动 |
| 卡在 0% 很久 | SoftwareDistribution 损坏 | 停服务 → 清 Download → 重启服务 |

## Step 3: 修复顺序（从轻到重）

1. 重启（真的重启，不是关机再开——快速启动会跳过）
2. `DISM /Online /Cleanup-Image /RestoreHealth`
3. `sfc /scannow`
4. 重置更新组件（停 wuauserv/BITS/cryptSvc → 重命名 SoftwareDistribution 与 catroot2 → 重启服务）

**第 4 步会丢更新历史，先征得同意。**

## Step 4: 不推荐的做法

- 用第三方「更新修复工具」一把梭
- 直接删除 `C:\Windows\SoftwareDistribution` 整个目录（服务没停会损坏状态）
- 长期关闭更新（安全风险，应由用户明确决定）

## Step 5: 报告

给出「当前状态（待重启/失败码）→ 建议动作 → 预期结果」，并说明哪些步骤不可逆。