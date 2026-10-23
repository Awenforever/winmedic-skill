# 启动项臃肿

## 适用
「开机弹一堆」「右下角一堆图标」「开机自启太多」。

## Step 1: 只读枚举

```powershell
Get-CimInstance Win32_StartupCommand | Select Name,Command,Location,User | Format-Table -AutoSize
Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' } | Select TaskName,TaskPath | Format-Table
```

## Step 2: 分类，不要一刀切

| 类型 | 例子 | 建议 |
|---|---|---|
| 安全软件 | 火绒、Defender | **保留** |
| 输入法 / 驱动面板 | 搜狗、罗技、Realtek | 保留 |
| 同步/网盘 | OneDrive、百度网盘 | 可禁用（改用按需启动） |
| 更新器 | *-updater、Update.exe | 可禁用（仅失去自动更新） |
| 厂商助手 | Lenovo Vantage、游戏启动器 | 可禁用 |
| 未知 | 无签名、路径在临时目录 | 先查清楚，可疑则保留并建议扫描 |

## Step 3: 处置方式（按可逆性排序）

1. 任务管理器「启动」页 → 禁用（**最可逆**，推荐）
2. 计划任务 → 禁用触发器
3. 删除启动项（不可回滚）——**仅在用户明确要求时**

## Step 4: 报告

列出「名称 → 作用 → 建议（保留/禁用/待查）→ 依据」。不要只说「禁用了 12 项」。

## 红线

- 不碰安全软件的自启
- 不碰输入法、显卡驱动的自启
- 无法识别来源的程序不要直接禁用，先查签名与路径