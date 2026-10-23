# VPN / 代理故障

## 适用
「开了代理就上不了网」「VPN 连上了但没网」「git/npm 拉不动」「clash 关了之后全断」。

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set network
Get-ChildItem Env: | Where-Object { $_.Name -match 'PROXY' } | Format-Table
git config --global --get http.proxy
npm config get proxy
```

重点看 `probe.proxy-config.summary.consistent`：**多处代理配置不一致是最常见的元凶**。

## Step 2: 分清三层代理

| 层 | 谁在用 | 查看方式 |
|---|---|---|
| WinINET（系统代理） | 浏览器、多数 GUI 程序 | 设置 → 网络和 Internet → 代理 |
| WinHTTP | 服务、部分安装器、git 有时 | `netsh winhttp show proxy` |
| 应用自有配置 | git / npm / pip / Docker | 各自的 config 命令 |

**关掉代理软件后，这三层不会自动清理干净**——这是「关了代理反而全断」的原因。

## Step 3: 典型场景处置

| 场景 | 处置 |
|---|---|
| 代理端口变了 | 同步改 WinINET / WinHTTP / 应用配置（引擎的 `scripts/gh-setup.ps1` 是同类做法） |
| 关闭代理后全断 | 检查 WinHTTP 是否还指着已关闭的端口：`netsh winhttp reset proxy` |
| VPN 连上没网 | 看路由表 `route print`，确认默认路由是否被虚拟网卡抢走 |
| 只有 git 不行 | `git config --global --get http.proxy`；很多工具不读系统代理 |
| 只有浏览器不行 | 浏览器可能用了独立代理扩展或 PAC |

## Step 4: 红线

- 不要为了「修网络」关防火墙或删安全软件
- 不要长期把代理指向无法验证的第三方节点
- 改代理前记录原值，便于回滚

## Step 5: 报告

给出「三层代理当前值 → 不一致点 → 统一后的值 → 验证方式」。