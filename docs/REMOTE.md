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
- SSH 传输路径已在真实远端验证（ustc-wjh / DESKTOP-CN7P93M，Win11 Pro，11.8 s）
- 大探针集（`--set all`）在远端可能数分钟，注意 `--timeout`
## 踩坑记录（2026-10-24 首次真实远端联调）

| 现象 | 根因 | 修法 |
|---|---|---|
| Out-Null 不是内部或外部命令 | 远端 shell 是 cmd，双引号与管道被 cmd 解析；PS 5.1 传原生参数会丢内嵌双引号 | 远端命令改为无引号、无管道 |
| scp: usage: ... | cmd /c echo %TEMP% 回传值尾部带引号，目标串被破坏 | 清洗引号并校验盘符格式 |
| 脚本首行变成 Stop = 'Stop' | 赋值串里的变量在本地就被展开了 | 改用单引号字面量 |
| probe 跑完但没有 findings | -File 用单引号，cmd 不剥单引号，路径带引号导致脚本没执行 | 路径无空格时裸写（Format-RemotePathArg） |

教训：远端默认 shell 可能是 cmd / Git Bash / 其他，不能假设 POSIX 引号语义。