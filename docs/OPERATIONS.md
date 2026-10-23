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