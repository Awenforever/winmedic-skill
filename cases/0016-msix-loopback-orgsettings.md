# 0016 MSIX 应用「无法加载组织设置」：运行时包缺 loopback 豁免

> 平台：Windows 11（DESKTOP-CN7P93M / `ustc-wjh`）｜应用：Codex MSIX `OpenAI.Codex 26.1111.2228.0`
> 症状：应用更新重启后弹「无法加载组织设置。应用已暂停…网络连接、代理或防火墙可能导致无法访问」，点重试无效；此前短暂正常过，之后复发。

## 1. 症状

- 弹窗文案指向网络/代理，但浏览器与其他应用网络正常
- 「重试」无效；「退出登录」无效
- 发生过多次，中间一度恢复，随后再次复发

## 2. 环境

- 应用为 MSIX 商店包，进程名 `ChatGPT.exe`（Chromium），运行在 Desktop AppX 容器
- 伴随 4 个 `OpenAI.CodexPrimaryRuntime.*` 依赖包，**版本随主包每次更新而变**
- Clash Verge `mixed-port 7897`，系统 WinINet 代理指向它；WinHTTP 为「直接访问」
- Tailscale 在线，代理出口是 tailnet IP（`100.x`）

## 3. 采集（只读）

```powershell
Get-AppxPackage -Name 'OpenAI.Codex*' | Select Name,Version
CheckNetIsolation.exe LoopbackExempt -s            # 看 openai 条目
Get-NetTCPConnection | Where-Object OwningProcess -in (Get-Process ChatGPT).Id
Resolve-DnsName chatgpt.com; Resolve-DnsName api.openai.com
```

关键观测：

- 故障时 `ChatGPT.exe` 有 7 个进程但 **0 条 TCP 连接**，且不在连 7897 的进程清单里
- 豁免表 171 条里 openai 只有主包与 chatgpt-desktop，**4 个 PrimaryRuntime 包族 0 条**
- `.codex` 下存在 `.codex-provisioning-*.guard`（0 字节），被 `codex-windows-sandbox-service` 独占

## 4. 假设与排除

| 假设 | 判定 | 依据 |
|---|---|---|
| 代理没开 / 端口错 | 排除 | 7897 在听，`curl -x` 得 200 |
| 应用没走代理 | 排除 | 恢复后连接直接落在 `127.0.0.1:7897`（WinINet） |
| 系统 DNS 被污染 | **部分成立** | openai 域名解析到 Facebook 段；但走代理时不依赖本地 DNS，故非本次直接原因 |
| WinHTTP 直连导致失败 | 排除 | Codex 是 Chromium（WinINet）+ Rust（env proxy），都不走 WinHTTP |
| 运行时包缺 loopback 豁免 | **成立** | 补豁免后立即恢复 |

## 5. 处置

1. 给当前**所有** `CodexPrimaryRuntime` 包族加 loopback 豁免（需管理员）：

```powershell
foreach ($p in Get-AppxPackage | Where-Object Name -like 'OpenAI.CodexPrimaryRuntime*') {
    $arg = '-n=' + $p.PackageFamilyName          # 必须加括号，否则被拆成多个参数 → 参数无效
    & CheckNetIsolation.exe LoopbackExempt -a ($arg)
}
```

2. 释放 guard 句柄：先停 `codex-windows-sandbox-service`，否则该 0 字节文件删不掉（`Remove-Item` 与 `[IO.File]::Delete` 均报「正由另一进程使用」）
3. 在**交互会话**重新拉起应用（SSH 属 session 0，`Start-Process shell:AppsFolder\...` 拉不起来）

## 6. 结果

- 弹窗消失，应用进入主界面；guard 计数 0 且未重建
- 连接恢复：`to7897` 有 8 条；openai 豁免 6 条
- tailnet、系统代理、路由均未受影响

## 7. 教训

- **loopback 豁免按 PackageFamilyName 记，而 MSIX 依赖包每次更新都换家族名** → 豁免不继承，这就是「好了又复发」的机制
- 复发自查一行：`CheckNetIsolation LoopbackExempt -s | findstr /i openai`，正常应有「主包 + 各运行时包 + chatgpt-desktop」
- 应用报「网络/代理问题」时，先看**它有没有任何 TCP 连接**；0 连接说明它根本没在试，别去改代理
- `CheckNetIsolation` 的 `-a`/`-n=` 在 PowerShell 里必须写成 `('-n=' + $pfn)`，不加括号会报「参数无效」
- 能彻底关闭复发：用 SYSTEM 计划任务幂等补豁免（见 §8）

## 8. 彻底关闭复发：幂等守护任务

**关键约束：MSIX 包是 per-user 安装，`SYSTEM` 账户的 `Get-AppxPackage` 看不到用户包**，所以守护任务必须用**用户账户 + 最高权限**跑，不能用 SYSTEM。

脚本落点 `C:\ProgramData\winmedic\codex-loopback-guard.ps1`（只加不减、不动任何网络配置）：

```powershell
$state = (& CheckNetIsolation.exe LoopbackExempt -s 2>&1 | Out-String)
foreach ($p in Get-AppxPackage | Where-Object { $_.Name -like 'OpenAI.Codex*' }) {
    if ($state -match [regex]::Escape($p.PackageFamilyName)) { continue }
    & CheckNetIsolation.exe LoopbackExempt -a ('-n=' + $p.PackageFamilyName) | Out-Null
}
```

任务注册（登录时 + 每日 12:00，幂等）：

```powershell
$p = New-ScheduledTaskPrincipal -UserId '<域>\<用户>' -LogonType Interactive -RunLevel Highest
$t1 = New-ScheduledTaskTrigger -AtLogOn -User '<域>\<用户>'
$t2 = New-ScheduledTaskTrigger -Daily -At 12:00
Register-ScheduledTask -TaskName 'Winmedic-Codex-Loopback-Guard' -Action $act -Trigger @($t1,$t2) -Principal $p -Force
```

### 实测：上线即抓到一次复发

```
2026-11-17 17:33:43 added 1: OpenAI.CodexPrimaryRuntime.v26-1116-1220-0_3k8sg7r9htsxt (v26.1116.1220.0)
```

当天上午修复时存在的运行时包是 26-1026 / 26-1030 / 26-1105 / 26-1110 四个；守护任务首次运行就发现**又多出 `v26-1116-1220-0`**，并自动补上豁免。这直接印证了复发机制，也说明手动修复**必然**会被下一次更新冲掉。

### 验证

```powershell
CheckNetIsolation LoopbackExempt -s | findstr /i openai   # 应覆盖：主包 + 每个运行时包 + chatgpt-desktop
```

回滚：`Unregister-ScheduledTask -TaskName 'Winmedic-Codex-Loopback-Guard'`；如需撤销某条豁免用 `LoopbackExempt -d -n=<包族>`。
