# PB-503 网络链路鉴别（某软件一直转圈 / 连不上）

> 症状：某个应用反复「正在连接 / Reconnecting / 等待网络」，或报「error sending request」「connection failed」。
> 原则：**先分层证明哪一跳断了，再谈修**。不要一上来就改配置。

## 分层模型

按顺序逐层验证，前一层不通就不要看后一层：

```
1 解析   DNS 给出的 IP 对不对
2 直连   TCP 443 能不能通
3 代理   显式走代理能不能通
4 长连   持续传输会不会中途停滞
5 应用   进程实际连的是谁、连接是否在抖
```

## 每层怎么做（只读）

### 1 解析

```powershell
Resolve-DnsName chatgpt.com -Type A | Select -Expand IPAddress
```

判读：出现 **108.160.x.x（Dropbox 段）**、**103.240.182.x** 这类与厂商无关的地址，基本可判 DNS 污染。

### 2 直连

```powershell
Test-NetConnection chatgpt.com -Port 443 | Select TcpTestSucceeded
curl.exe -sS -o NUL -w "%{http_code} %{time_total}" --max-time 10 --noproxy "*" https://chatgpt.com/
```

判读：`TcpTestSucceeded=False` 或 `http_code=000`（超时）→ 直连不可用。

### 3 代理

先找端口：系统代理（WinINET）、环境变量、监听端口三处对照。

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select ProxyEnable, ProxyServer
netsh winhttp show proxy
Get-NetTCPConnection -State Listen | Where LocalPort -in 7890,7891,7897,10808,10809,8136
```

再显式走代理：

```powershell
curl.exe -sS -o NUL -w "%{http_code} %{time_total}" --max-time 20 `
  --proxy http://127.0.0.1:7897 https://api.openai.com/v1/models
```

判读：
- `401 / 403 / 404` 都算 **链路通**（能到服务器）
- `000` 才是真正连不上
- 需要鉴权的域名加 `-A "Mozilla/5.0 …"` 与 `-H "Accept: application/json"`，否则可能拿到 Cloudflare 的 403 页面而误判

### 4 长连接（最容易被忽略）

短请求全过、长连接却断，是「反复重连」的典型元凶。

```powershell
1..5 | ForEach-Object {
  curl.exe -sS -o NUL -w "%{http_code} %{time_total} %{size_download}`n" --max-time 40 `
    --proxy http://127.0.0.1:7897 "https://speed.cloudflare.com/__down?bytes=30000000"
}
```

判读：`size_download` 明显小于请求字节数（例如 40 秒只下 7.7 MB）就是**中途停滞**。停滞率 > 10% 就足以让流式应用不断重连。

### 5 应用实际行为

```powershell
$p = Get-Process codex
Get-NetTCPConnection -OwningProcess $p.Id | Select RemoteAddress, RemotePort, State

# 看连接是否在抖（60 秒采样，每秒一次，记录到代理端口的连接数）
1..60 | ForEach-Object {
  @(Get-NetTCPConnection -OwningProcess $p.Id | Where { $_.RemotePort -eq 7897 -and $_.State -eq 'Established' }).Count
  Start-Sleep -Seconds 1
}
```

判读：连接数在 4 → 0 → 3 之间反复，就是**应用侧重连循环**；配合第 4 层停滞率即可定性。

## 常见根因对照

| 现象 | 根因 | 修法 |
|---|---|---|
| 直连 000，代理 401 | 直连被阻断，应用没走代理 | 设 `HTTPS_PROXY` 或开 TUN |
| 代理短请求秒回、长连接停滞 | 节点质量差 / 中转限速 | 换节点、用自动选择组 |
| 代理全 403 | 出口 IP 被 Cloudflare 拦 | 换出口节点 |
| 改了环境变量但应用没生效 | 从 Explorer 启动，继承了旧环境 | 重开 Explorer 或从带环境的进程启动 |
| 只有某台机器出问题 | DNS 服务器不同 / 路由不同 | 对照 DNS 与 `tracert` |

## 安全边界

- 前四层**全部只读**：读配置、读连接、发测试请求
- 不改代理设置、不重启服务、不切节点——除非用户明确要求
- 测试请求要控制频率与时长，避免把「测试」变成「压测」
- 不要在目标机上落临时文件；需要多行脚本时用 `-EncodedCommand` 传输

## 何时该怀疑「不是网络」

- 应用日志里是 401/403 而非传输错误 → 看认证，不看链路
- 同机其它依赖同一域名的应用正常 → 看该应用自己的代理设置
- 短请求也全失败 → 回到第 3 层，先确认代理进程还活着

## 实测来源

2026-10-25 用于 `ustc-wjh` 上 Codex 反复 Reconnecting 的排查：直连 000、代理 401 正常、30MB 下载 5 次中 1 次停在 7.7 MB、Codex 到 7897 的连接数 60 秒内 4→0→3。结论是链路长连接不稳定，而非应用缺陷。
