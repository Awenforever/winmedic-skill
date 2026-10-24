# Outlook 故障

## 适用
「Outlook 打不开」「收不到新邮件」「一直弹配置窗口」「打开很卡」「提示 OST 文件损坏」。

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set mail
```

读 `probe.mail-clients`：
- `outlookInstalled` / `officeVersion`：装没装、哪个版本
- `profiles` / `defaultProfile`：配置文件是否存在
- `dataFiles`：OST/PST 列表与体积（`verdict`：oversize ≥50 GB、large ≥25 GB）
- `problemAddinCount`：未加载/已禁用的加载项

## Step 2: 按症状分流

| 症状 | 常见原因 | 顺序 |
|---|---|---|
| 一启动就弹配置 | 配置文件损坏 / 账户缺失 | 新建配置文件 |
| 收发卡住、进度不动 | 加载项冲突 | 安全模式验证 |
| 打开很慢、越用越大 | OST 过大 | 压缩 / 重建 OST |
| 提示 OST 损坏 | 文件损坏或磁盘错误 | 先 scandisk 再重建 |
| 完全打不开 | Office 安装损坏 | 快速修复 → 联机修复 |

## Step 3: 安全模式（最快的加载项排查）

```powershell
Start-Process outlook.exe -ArgumentList '/safe'
```

- 安全模式下正常 → **加载项问题**，逐个禁用定位
- 安全模式下也异常 → 配置文件或数据文件问题，跳到 Step 4

## Step 4: 重建配置文件（不丢邮件）

1. 控制面板 → 邮件 → 显示配置文件 → 添加新配置文件并设为默认
2. 重新添加同一账户（IMAP/Exchange 会从服务器重新同步）
3. **确认新配置能收到邮件后**，再删除旧配置文件

**POP3 账户要格外小心**：邮件可能只存在本地 OST/PST 里，删配置前先导出。

## Step 5: 处理过大的 OST

- 先确认账户类型：Exchange/IMAP 的 OST 可从服务器重建，**POP3 不行**
- 保留期设置越长，OST 越大（默认 1 年，可调整为 3–6 个月）
- 重建：关闭 Outlook → 重命名 OST（不要直接删）→ 重开 Outlook 让它重建

## Step 6: 报告

给出「版本/配置/数据文件体积/加载项状态 → 判断 → 执行了什么 → 验证结果」。

## 红线

- 不直接删 OST/PST（先重命名保留）
- 不在未确认账户类型时重建数据文件
- 不动企业环境的 Exchange 服务器设置