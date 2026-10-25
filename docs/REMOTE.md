# 远程会话层

> 目的：让 Agent 在**远端机器**上采集证据，把结论带回本地。这是「主治医生」能力的地基——用户的痛点几乎都在远端。

## 用法

```powershell
.\engine\winmedic.ps1 remote --target <ssh别名或user@host> --set intake
.\engine\winmedic.ps1 remote --target augenstern-adm --set network --json
.\engine\winmedic.ps1 remote --target loopback-test --via local --set storage   # 自测用
```

参数：

| 参数 | 说明 |
|---|---|
| `--target` | SSH 别名（走 `~/.ssh/config`）或 `user@host` |
| `--set` | 探针集，默认 `intake` |
| `--via` | `ssh`（默认）或 `local`（loopback，给 CI/自测用） |
| `--timeout` | 远端采集超时秒数，默认 300 |
| `--keep` | 保留远端临时目录（排障用），默认清理 |

## 它做了什么

1. `ssh -o BatchMode=yes` 探测可达（**绝不弹密码提示**）
2. 打包最小运行集（engine / catalog / VERSION）→ `scp` 到远端 `%TEMP%\winmedic-<runId>`
3. 上传引导脚本：设 `CDRIVE_HOME` 到临时目录、`ExecutionPolicy Bypass`、UTF-8 输出
4. 远端执行只读 `probe`，`scp` 回传 findings
5. 落库为 `state/remote-<别名>-<set>-findings.json`，每个探针打 `origin=remote:<别名>`
6. 默认删除远端临时目录（`--keep` 保留）

## 安全边界

- **只读**：本版本不支持远程 `apply`
- **不碰凭据**：只用既有 SSH key/agent；`BatchMode=yes` 保证不会卡在密码提示
- **来源可辨**：远端 findings 带 `origin`；本地 `apply` 必须拒绝 `origin=remote:*` 的条目
- **不残留**：远端临时目录默认清理

## 失败处理

| 情况 | 退出码 | 说明 |
|---|---|---|
| 缺 `--target` | 2 | 用法错误 |
| 不可达 / 传输失败 / 回传缺失 | **8** | 附带排查顺序提示 |

排查顺序：1) ssh 别名能否解析 → 2) 目标机是否开机 → 3) `ssh -o BatchMode=yes <target> echo ok`。

## 已知限制

- 远端需 PowerShell 5.1+（引擎本身要求）
- 远端必须是 Windows（本 skill 的定位）
- SSH 传输路径已在真实远端验证：本机 VMware VM `win11-test`（Windows 11 Test / DESKTOP-GB7NLMT / Win11 Pro 26200），冷启动首采 152.6 s，9 个探针全部 `origin=remote:win11-test`
- 大探针集（`--set all`）在远端可能数分钟，注意 `--timeout`
## 踩坑记录（2026-10-24 首次真实远端联调）

| 现象 | 根因 | 修法 |
|---|---|---|
| Out-Null 不是内部或外部命令 | 远端 shell 是 cmd，双引号与管道被 cmd 解析；PS 5.1 传原生参数会丢内嵌双引号 | 远端命令改为无引号、无管道 |
| scp: usage: ... | cmd /c echo %TEMP% 回传值尾部带引号，目标串被破坏 | 清洗引号并校验盘符格式 |
| 脚本首行变成 Stop = 'Stop' | 赋值串里的变量在本地就被展开了 | 改用单引号字面量 |
| probe 跑完但没有 findings | -File 用单引号，cmd 不剥单引号，路径带引号导致脚本没执行 | 路径无空格时裸写（Format-RemotePathArg） |

教训：远端默认 shell 可能是 cmd / Git Bash / 其他，不能假设 POSIX 引号语义。
## 远端处置与还原

只读诊断之外，确需在远端动手时：

```powershell
# 1) 远端采集 -> 2) 基于远端 findings 本地出计划
.\engine\winmedic.ps1 remote --target <别名> --set storage
.\engine\winmedic.ps1 plan --from C:\ProgramData\cdrive\state\remote-<别名>-storage-findings.json

# 3) 本地执行会被拒绝（安全不变式）
.\engine\winmedic.ps1 apply --ids R2 --yes        # exit 2

# 4) 远端执行
.\engine\winmedic.ps1 remote-apply --target <别名> --plan <plan.json> --ids R2 --yes

# 5) 远端还原
.\engine\winmedic.ps1 remote-restore --target <别名> --journal <runId> --yes
```

### 安全不变式

1. **计划带来源**：`plan.origin` 与每个 item 的 `origin` 都会记录（`local` 或 `remote:<别名>`）
2. **本地拒绝**：含非 local 来源的计划，本地 `apply` 在权限检查**之前**即拒绝（退出码 2）
3. **远端放行**：远端引擎需要 `--allow-remote-origin remote:<自己>` 才执行，其他来源照样拒绝
4. **持久隔离区**：远端隔离区与审计日志存放在 `C:\ProgramData\winmedic-remote-state`，**不随暂存目录清理**
5. **审计可回收**：执行后自动把远端 journal 拉回本地 `state/remote-<别名>-journal-<runId>.jsonl`

### 实测记录（win11-test VM）

- 120 MB Edge 缓存：远端移入隔离区（目录消失）→ `remote-restore` → 3 个文件 SHA256 与原负载一致
- 重复 restore 正确报「隔离区文件已不存在」

## 无落盘只读体检（remote-probe）

只想「看看」，不想在对方机器上留下任何文件时用这个：

```powershell
winmedic.ps1 remote-probe --target <别名> --set net-link
```

它把探针源码 **GZip 压缩 + base64** 后经 `EncodedCommand` 送到远端执行（cmd 命令行有 8191 字符上限），
**不在目标机创建任何文件**，结果只落本地 `state/remote-<别名>-netlink-findings.json`。

输出四项事实：

| 项 | 含义 |
|---|---|
| DNS | 每个目标域名是否解析成功 |
| 直连 443 | 不经代理能否建立 TCP |
| 代理 | 端口、是否可达、HTTP 状态 |
| 长连接采样 | N 次传输中完整/停滞的数量与停滞率 |

实测（ustc-wjh）：`DNS=True 直连=False 代理可达=True HTTP=401 采样 3/3 停滞率=0`。
