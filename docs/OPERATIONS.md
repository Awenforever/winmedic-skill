# 运维与远程注意事项

## 远程执行（SSH）

Windows OpenSSH 默认 shell 是 cmd，管道与引号会被吃掉。**统一用 base64 传参**：

```powershell
# 生成（本地）
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
# 执行（远程）
ssh host powershell -NoProfile -EncodedCommand $b64
```

### 命令行长度上限

约 8191 字符。UTF-16LE 的 base64 膨胀 2.67 倍，**单段脚本控制在 3000 字符以内**，超了拆段。
症状：命令静默失败、无任何输出。

## 权限

| 账号 | 能力 |
|---|---|
| 普通用户 | 只读探针可用；apply 返回码 3 |
| Administrators 成员（SSH） | 完整令牌（实测 IsInRole 为 True） |

普通用户下 WMI 查询可能返回**空对象而非报错**，勿误判。

## 会话限制

SSH 会话是 Session 0：从 SSH 启动的 GUI 程序用户看不见，且 SSH 断开后进程消失。**不要试图远程帮用户打开程序。**

## 笔记本睡眠

连接超时但 ping 正常 → 大概率是睡眠。需用户同意后设置：

```powershell
powercfg /change standby-timeout-ac 0
```

## 代理

GitHub 直连通常不通，git 的 http.proxy 端口会随代理软件漂移。发布前执行：

```powershell
.\scripts\gh-setup.ps1
```
## 安全软件误杀（真实踩坑）

2026-10-25：火绒把 `engine/lib/Remote.ps1` 隔离，表现是引擎突然报「找不到文件/命令」，排查半天才发现文件不见了。

**处置**：
1. 把仓库目录加入杀软信任区
2. `winmedic.ps1 doctor` 现在会检查 `engine/MANIFEST.txt`：文件缺失或为空会直接提示「可能是安全软件隔离」

`MANIFEST.txt` 由发布脚本生成，列出引擎全部 `.ps1`；加文件后记得同步清单（或跑 `scripts/refresh-manifest.ps1`）。

## 推送：端口会漂移，别写死

系统代理端口会变（实测从 8136 漂到 50575）。写死端口或用 `-c http.proxy=` 绕过配置，都会表现为「推送失败」。

```powershell
.\scripts\push.ps1                 # 自动同步系统代理 → 推送 → ls-remote 校验
.\scripts\gh-setup.ps1 -Show       # 只看当前系统代理与 git 配置
```

`push.ps1` 会重试并在最后用 `ls-remote` 确认远端 HEAD 与本地一致，避免「以为推上去了」。

## 安装到宿主后的验收清单（DSH）

每次发版、每次装到新宿主，跑一条命令：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-host.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\verify-host.ps1 -Json   # 机器可读
```

八项检查（全部 PASS 才算出货）：

| # | 检查 | 失败意味着 |
|---|---|---|
| 1 | SKILL.md 存在 | 安装不完整 |
| 2 | engine 存在 | 同上 |
| 3 | `Remote.ps1` 可读 | 被安全软件拦截 → **远端功能降级** |
| 4 | VERSION 与引擎版本一致 | 覆盖不完整（升级残留） |
| 5 | frontmatter 可被 YAML 解析 | 技能不会出现在宿主目录（病例 0011） |
| 6 | doctor 通过 | 环境/权限问题 |
| 7 | MCP 握手 + 中文可读 | MCP 未注册、或编码不一致（病例 0011） |
| 8 | MCP 已注册到 profile | 配置没写进去 |

### 第 3 项失败怎么办

现象：`Remote.ps1` 缺失或读出来是空。

1. 把**技能目录**加入杀毒软件信任区：`%USERPROFILE%\.dsh\skills\winmedic`
2. 从仓库或安装包恢复文件：

```powershell
Copy-Item .\engine\lib\Remote.ps1 "$env:USERPROFILE\.dsh\skills\winmedic\engine\lib\" -Force
```

3. 重跑 `verify-host.ps1`

其余功能（probe/plan/apply/verify/restore/trend/diagnose）不受影响，只有 `remote*` 命令会返回退出码 4 并提示原因。

### 仓库目录也被拦截时

两种兜底已经在仓库里：

1. `release.ps1` 打包前会检查受跟踪文件，缺失的自动从 `git show HEAD:<path>` 还原（实测可从零恢复）
2. `.githooks/pre-commit` 阻止把受保护目录（engine/catalog/playbooks）的**删除**提交进历史；确需删除时用 `ALLOW_PROTECTED_DELETE=1 git commit`

钩子启用方式（新克隆后一次）：

```powershell
git config core.hooksPath .githooks
```

