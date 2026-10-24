# 病例 0001：git push 失败，但浏览器能上网

## 1. 症状

- 用户原话：「push 不上去，报错 128」
- 触发条件：代理软件换过端口之后
- 误判过的方向：以为是 GitHub 认证问题（其实认证正常）

## 2. 环境

| 项 | 值 |
|---|---|
| 主机 | 本机（Windows 11 Pro） |
| 采集方式 | local |
| 引擎版本 | 修复后 v2.x |

## 3. 采集（证据）

```powershell
winmedic.ps1 probe --set workloads   # 内含 probe.proxy-chain
git config --global --get http.proxy
```

关键输出：

```
system(WinINET) = http://127.0.0.1:8136
git             = http://127.0.0.1:13499   <- 旧端口，已死
```

## 4. 假设与排除

| 假设 | 判据 | 结果 |
|---|---|---|
| GitHub 认证失效 | `git ls-remote` 也失败，但同凭据在别处可用 | 排除 |
| 网络不通 | 浏览器可访问同一站点 | 排除 |
| **代理层不一致** | 系统层 8136、git 层 13499 | **支持** |

## 5. 处置

| 动作 | 影响面 | 可回滚 |
|---|---|---|
| `git config --global http.proxy http://127.0.0.1:8136`（https 同） | 仅 git | 是（记下原值即可） |
| 用 `scripts/gh-setup.ps1` 从注册表读当前系统代理并同步 | 同上 | 是 |

## 6. 结果

- 是否解决：是，push 恢复
- 验证方式：`git ls-remote <repo> HEAD` 退出码 0
- 残留问题：代理软件若再换端口，会再次漂移

## 7. 教训

- **先看五层代理，不要先怀疑凭据**
- 这类故障的典型叙述是「关了代理反而全断」——因为某一层还指着旧端口
- 已固化为 `probe.proxy-chain` + playbook `apps-proxy-chain`