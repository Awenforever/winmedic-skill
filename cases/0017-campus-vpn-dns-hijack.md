# 0017 校园网 VPN 劫持 DNS：应用下载失败但浏览器正常

> 平台：Windows 11（DESKTOP-KFSCV8C / `invictus`）｜症状：IDM、Steam、微信输入法在线安装器全部下载失败，浏览器下载正常。
> 结论：校园网 VPN 客户端（Panabit TUN）把自己配置的 DNS 地址也路由进隧道，导致 DNS 查询从校园网出口发出，公共 DNS 按来源就近调度，返回了移动宽带到不了的教育网 CDN 节点。

## 1. 症状

- IDM 下载报 `Error`，错误码 `10060`
- Steam 「未知错误」，网络 0 bps
- 微信输入法在线安装器「更新未成功·请重试」，进度停在 0%
- **同一个文件用浏览器下载就成功**
- 开系统代理无效

## 2. 环境

- 双出口：WLAN（移动宽带，默认路由）+ 校园网 VPN 客户端 **Panabit**（TUN）
- Panabit 组成：Flutter 界面 + `panabit-service.exe`（LocalSystem 服务）+ `wintun` 内核驱动
- 虚拟网卡 `PanabitTun Tunnel`，本端 `10.10.9.146/32`，对端 `100.100.1.4`

## 3. 采集（只读）

```powershell
# 1) 应用到底连谁（关键）
Get-Process | Where ProcessName -match 'wetype' | ForEach-Object {
    Get-NetTCPConnection | Where OwningProcess -eq $_.Id
}
# 2) 同一域名在不同 DNS 上返回什么
Resolve-DnsName download.z.weixin.qq.com -Type A -Server 202.38.64.56 -DnsOnly
Resolve-DnsName download.z.weixin.qq.com -Type A -Server 223.5.5.5    -DnsOnly
# 3) 这些 IP 到底通不通
Test-NetConnection 43.171.94.227 -Port 443
# 4) 哪个接口在提供 DNS、谁的 metric 更低
Get-DnsClientServerAddress -AddressFamily IPv4
Get-NetIPInterface -AddressFamily IPv4 | Sort InterfaceMetric
# 5) VPN 客户端加了哪些路由
Get-NetRoute | Where InterfaceAlias -eq 'Panabit'
```

关键观测：

- 安装器直连 `43.171.94.227:443`（`SynSent` 半开），**完全没有连 `127.0.0.1:7892`** → 它不读系统代理
- 校园 DNS 返回 `43.171.x`（全部不可达），公共 DNS 返回 `112.x`（全部可达）
- Panabit 路由表里除了校园网段，还有 **`223.5.5.5/32`、`119.29.29.29/32` → 隧道网关**

## 4. 假设与排除

| 假设 | 判定 | 依据 |
|---|---|---|
| 代理没开/端口错 | 排除 | 7892 在听，`curl -x` 得 200 |
| 应用走了代理但代理不通 | 排除 | 抓连接证明它压根没连代理端口 |
| DNS 被污染 | 排除 | 各 DNS 都能解析，只是返回**不同 CDN 节点** |
| 线路整体故障 | 排除 | 浏览器能下载、IPv6 能下载、走代理能下载 |
| 磁盘满/临时目录不可写 | 排除 | C: 43 GB、temp 可写 |
| 换公共 DNS 就能解决 | **部分错误** | 换了仍失败——VPN 把该 DNS 也路由进隧道 |
| VPN 提供 DNS 导致查询走错出口 | **成立** | 禁用其 DNS 后立刻恢复 |

## 5. 处置

1. **VPN 客户端 DNS 设为「禁用 DNS」**（不是「自定义 DNS」）
   - 「自定义」只是把地址写进接口，VPN 仍会给它加 `/32` 隧道路由
   - 「禁用」后系统回落到物理网卡 DNS，查询从物理出口发出
2. 物理网卡（WLAN）DNS 设公共：`223.5.5.5` + `119.29.29.29`
3. IPv6 DNS 一并换掉（原 `240c::6666` 对 AAAA 查询零应答）：`2400:3200::1` + `2402:4e00::`
4. 关闭临时系统代理（它对这个应用无效）

## 6. 结果

- 微信输入法 `3.0.2.44` 安装成功，服务 `WeType Management Service` 运行
- 微信 CDN 解析稳定在 `112.x` 与 IPv6，下载 200 / 2.86 MB
- 校园网业务（科大 LLM `api.llm.ustc.edu.cn` → `114.214.240.204`）**不受影响**：它走的是 `114.214.192.0/18 → Panabit` 路由，与 DNS 无关
- 禁用 DNS 后 VPN 自动删除了那两条 DNS `/32` 隧道路由

## 7. 教训

- **「浏览器能下、其他应用不能下」是 DNS 返回不同地址族/节点的强信号**，不是应用坏了
- **VPN/代理客户端会把配置的 DNS 地址也路由进隧道**（防泄漏设计）。只改 DNS 服务器地址没用，必须让它**不提供 DNS**
- 判断 DNS 好坏不能只看延迟：校园 DNS 4 ms 最快，却返回了不可达节点；**必须验证返回的 IP 是否可达**
- Windows 的 DNS 客户端**按接口发送查询**，不遵循普通路由表里的 `/32` 路由；但应用自己发的普通 UDP 查询会遵循——所以 `Resolve-DnsName -Server` 与实际解析结果可能不一致，别只看前者
- 这类客户端会周期性重置接口 metric（本例 `1 → 50` 被改回），**改 metric 不是可靠方案**
- 在线安装器普遍不读系统代理；想让它走代理只能靠 TUN/透明代理
- 排查顺序：先抓应用实际连的 IP → 再对比该域名在不同 DNS 下的返回 → 再测这些 IP 可达性 → 最后看路由与接口优先级
