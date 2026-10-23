# 打印机故障

## 适用
「打印机离线」「点了打印没反应」「队列卡住」「打印乱码」。

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set printers
```

看 `probe.printers`：
- `printer` 的 `verdict`（脱机 / 报错 / 缺纸 / 卡纸 / 耗材不足 / 正常）
- `workOffline` 为真 → 系统层面认为打印机不可用
- `spoolerStatus`：打印后台服务是否在跑
- `queuedJobs`：队列里卡了哪些任务

## Step 2: 按顺序排查

| 顺序 | 检查 | 处置 |
|---|---|---|
| 1 | 电源 / 网络 / USB | 物理层面先确认，别一上来就重装驱动 |
| 2 | 脱机状态 | 取消「脱机使用打印机」勾选 |
| 3 | 队列卡死 | 清空队列（见下） |
| 4 | Spooler 服务 | 重启服务 |
| 5 | 驱动 | 最后才动 |

## Step 3: 清空队列（安全做法）

```powershell
Stop-Service Spooler -Force
Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
Start-Service Spooler
```

**这是少数可以直接删的目录**（打印临时文件），但仍建议先停服务。

## Step 4: 重装驱动的正确顺序

1. 删除打印机（勾选「删除驱动程序」）
2. 重启
3. 装厂商官网驱动（不要用通用 PCL/PS 驱动凑合）
4. 加回打印机

## Step 5: 报告

给出「哪一层出问题 → 证据 → 做了什么 → 是否恢复」。
不要只说「已修复」。