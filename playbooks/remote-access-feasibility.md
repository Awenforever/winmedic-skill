# PB-505 远程可达性判断（Tailscale / 子网路由 / IPv6）

> 症状：想从 A 机访问 B 机，但连不上；或「手机装了 Tailscale 却进不了内网」。
> 原则：**先证明卡在哪一层**，不要先改防火墙或加 Funnel。

## 分层判断

```
1 账号层   两台设备是否在同一 Tailnet、是否都在线
2 地址层   Tailscale IP / 内网 IP / IPv6 哪个能通
3 路由层   目标网段有没有被 advertised + approved（子网路由）
4 设备层   发起方是否支持所需能力（Android 不能当子网路由器）
5 服务层   目标端口是否监听、服务是否只绑 127.0.0.1
6 策略层   防火墙 / ACL / 安全组
```

## 每层的只读验证

| 层 | 命令 | 判读 |
|---|---|---|
| 账号 | `tailscale status` | 对方是否 `active`，是否同一 tailnet |
| 地址 | `tailscale ping <peer>` | 直连/中继；不通说明不在同一虚拟网 |
| 路由 | `tailscale debug prefs`、管理台 Routes | 目标网段是否 advertised 且 approved |
| 设备 | 管理台设备详情 | Android/iOS **不能**启用子网路由 |
| 服务 | `Get-NetTCPConnection -State Listen` | 只看 `0.0.0.0`/`::`；只绑 `127.0.0.1` 的外部不可达 |
| 策略 | `Get-NetFirewallProfile`、管理台 ACL | 是否有显式拒绝 |

## 常见组合与结论

| 组合 | 结论 |
|---|---|
| 同 Tailnet、`tailscale ping` 通、端口在听 | 应用层问题，转 PB-503 |
| 同 Tailnet、ping 不通 | 设备离线 / key 过期 / ACL |
| 跨网段、未 advertised | 需要子网路由；发起方是手机则不可行 |
| 有公网 IPv6、双方都支持 | 可直连，不依赖中转 |
| 只能经中转 | 可用但延迟高，注意大文件传输 |

## 安全边界

- **不改**防火墙、不加 Funnel、不开公网端口，除非用户明确要求并理解暴露面
- 不把「能 ping 通」当成「服务可用」，必须验证目标端口
- 远程执行只读命令；写操作走 `remote-apply` 的既有确认流程

## 验证

- 从发起方实际访问一次目标服务（不是只 ping）
- 断开重连后仍可用
- 记录所用路径（直连/中继/子网路由），便于下次对照

## 关联

- PB-503 网络链路鉴别
- PB-502 VPN/代理排查
