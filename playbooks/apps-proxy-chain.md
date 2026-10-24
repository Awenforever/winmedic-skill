# 代理链路一致性

## 适用
「关了代理反而全断」「git 拉不动但浏览器能上」「npm/pip 装不上包」「装了好几个加速器之后网络就乱了」

## 为什么会有这个问题

Windows 上的代理**不是一处配置**，至少五层各自独立：

| 层 | 谁在用 | 在哪看 |
|---|---|---|
| system(WinINET) | 浏览器、多数 GUI 程序 | 设置 → 网络和 Internet → 代理 |
| WinHTTP | 系统服务、部分安装器 | `netsh winhttp show proxy` |
| git | git 自己 | `git config --global --get http.proxy` |
| npm | npm 自己 | `~/.npmrc` 里的 proxy |
| pip | pip 自己 | `%APPDATA%\pip\pip.ini` 里的 proxy |

**代理软件只改其中一两层**；卸载或换端口后剩下的层还指着旧地址，于是出现「代理关了反而全断」。

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set workloads
```

读 `probe.proxy-chain`：
- `consistent=false` 就是有冲突，`conflicts` 会列出哪几层不一致
- `clients` 是本机装的代理/加速器客户端（多客户端共存本身就容易互相覆盖配置）

## Step 2: 处置顺序

1. 先确定**唯一**要用的代理端口（例如 Clash Verge 的 8136）
2. 逐层改成同一个值
3. 改完再验证

```powershell
# 系统层：设置里改，或
# 应用层示例
git config --global http.proxy http://127.0.0.1:8136
git config --global https.proxy http://127.0.0.1:8136
# WinHTTP（需要管理员）
netsh winhttp set proxy 127.0.0.1:8136
# 想彻底直连：
# netsh winhttp reset proxy
```

## Step 3: 多加速器共存

本机同时装 Clash Verge / 极连云 / 小黑盒 / KK加速器 / Panabit / Tailscale 这类多个客户端时：

- **同一时间只开一个**系统级代理
- 游戏加速器通常只劫持特定进程，与全局代理冲突时表现为「游戏能连、网页打不开」
- Tailscale 是组网不是代理，但会改路由表，排障时要一起看

## Step 4: 验证

```powershell
Test-NetConnection 127.0.0.1 -Port 8136      # 端口在听吗
curl.exe -x http://127.0.0.1:8136 -I https://github.com   # 代理通不通
git ls-remote https://github.com/Awenforever/winmedic-skill HEAD
```

## Step 5: 报告

给出「五层各自的值 → 冲突点 → 统一后的值 → 验证结果」。

## 红线

- 不要为了「修网络」关防火墙
- 不要把代理指向来源不明的公共节点
- 改之前记下原值（本仓库的 `scripts/gh-setup.ps1` 就是按这个思路做的）