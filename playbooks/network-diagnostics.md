# 网络诊断

## 适用
「突然断网」「Wi-Fi 连着但打不开网页」「能上微信不能开网站」「DNS 出错」。

## 原则：先分层，别乱点

```
物理/链路 -> IP -> 网关 -> DNS -> 代理 -> 应用
```

**从下往上查，查到哪层断就停在哪层。**

## Step 1: 只读配置取证

```powershell
.\engine\winmedic.ps1 probe --set network
```

看 `probe.network-adapters`：哪些网卡 Up、有没有 IP、网关对不对。
看 `probe.dns-config`：DNS 服务器是不是被改成了奇怪的地址。
看 `probe.proxy-config`：系统代理与 WinHTTP 代理是否一致。

## Step 2: 连通性测试（由 Agent 显式执行，引擎不联网）

```powershell
ping <网关> -n 4                 # 链路与 IP
Resolve-DnsName www.baidu.com    # DNS
Test-NetConnection www.baidu.com -Port 443
```

| 现象 | 断点 | 处理 |
|---|---|---|
| ping 网关不通 | 链路 | 换线/重连 Wi-Fi/查交换机 |
| ping 网关通、DNS 不通 | DNS | 换 DNS（223.5.5.5 / 119.29.29.29） |
| DNS 通、443 不通 | 代理/防火墙 | 查代理配置与安全软件 |
| 只有某个网站不行 | 应用层 | 查 hosts、代理规则、证书 |

## Step 3: 常见坑

- **代理残留在 WinHTTP**：系统代理关了，但 `netsh winhttp` 还指着旧端口 → 部分程序上不了网
- **hosts 文件被写死**：某些「加速器」会往里塞记录
- **IPv6 优先失败**：换网络后临时禁用 IPv6 可验证
- **VPN 虚拟网卡抢路由**：断开 VPN 后路由表没恢复

## Step 4: 报告

给出「断在哪一层 → 证据 → 建议动作」，不要只说「网络没问题」。