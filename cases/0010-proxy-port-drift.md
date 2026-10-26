# 病例 0010：推送一直失败——不是网络坏了，是端口漂了

## 1. 症状

- `git push` 连续多次失败，退出码 128：
  `Failed to connect to github.com port 443 via 127.0.0.1 after 2043 ms`
- 换直连也不行：`ls-remote` 同样超时
- 当时的判断：**代理进程退出了 / 网络被阻断**，于是起后台循环反复重试，重试也只是重复失败

## 2. 环境

| 项 | 值 |
|---|---|
| 主机 | DESKTOP-KFSCV8C（本机） |
| 现象期 | 2026-10-25 22:00 – 2026-10-26 01:00 |
| 代理 | Clash 系（端口会漂移） |
| git 配置 | `http.proxy = http://127.0.0.1:8136`（陈旧） |

## 3. 采集（证据）

```powershell
# 1) 配置里写的是什么
git config --get http.proxy
# http://127.0.0.1:8136

# 2) 系统实际在用什么
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyServer
# 127.0.0.1:50575

# 3) 两个端口分别能不能用
curl.exe -sS -o NUL -w '8136 -> %{http_code}' --proxy http://127.0.0.1:8136 https://github.com/
curl.exe -sS -o NUL -w '50575 -> %{http_code}' --proxy http://127.0.0.1:50575 https://github.com/
# 8136 -> 000（连不上）
# 50575 -> 200   0.64s
```

## 4. 假设与排除

| 假设 | 判据 | 结果 |
|---|---|---|
| GitHub 被阻断 | 用当前系统代理 50575 访问 github.com | 排除（200，0.64 秒） |
| 代理进程退出 | `Get-Process` 显示 Clash 核心在跑；50575 在监听 | 排除 |
| **git 里的代理端口过期** | 配置 8136 vs 系统 50575，两个端口一死一活 | **成立** |
| 我绕过了配置 | 多次使用 `-c http.proxy=`（把代理置空） | 让问题更难发现 |

## 5. 处置

| 动作 | 影响面 | 可回滚 |
|---|---|---|
| `scripts/gh-setup.ps1`：把 git 代理同步为当前 WinINET 值 | git 全局两项 | 是 |
| 新增 `scripts/push.ps1`：同步代理 → 推送 → **ls-remote 校验** → 推 tag | 发布流程 | 是 |
| `docs/OPERATIONS.md` 写明「端口会漂移，别写死」 | 文档 | — |
| 修正历史分叉：`reset --soft` 把误 amend 的提交重建在线性历史上 | git 历史（未推送部分） | 是 |

## 6. 结果

```
main 已同步（第 1 次尝试）
tags 推送: 成功
local = 597f56b   remote = 597f56b
```

- 是否解决：是。之后所有推送走 `push.ps1`，不再手工指定端口

## 7. 教训

1. **工具的前提会过期**：端口、路径、凭据都可能变；把「前提」写死在命令里，就是把故障埋进未来
2. **「网络失败」先验证配置来源**：不要一上来就重试；先问「我用的这个地址，现在还有人听吗」
3. **绕过配置的快捷方式最坑**：`-c http.proxy=` 看起来是在排除干扰，实际是把唯一可用的通道也关了
4. **校验要看远端**：`push` 返回码可能骗人，`ls-remote` 对比 HEAD 才是事实
5. **误诊是连锁的**：这次先误判为「链路不稳（stallRate 0.333）」，而链路测量本身就走在一个错位的配置上——**输入的错会让诊断结论也错**
