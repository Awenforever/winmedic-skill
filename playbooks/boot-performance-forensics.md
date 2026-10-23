# 性能取证（卡顿 / 高占用）

## 适用
「电脑卡」「风扇狂转」「CPU/内存占满」「打开文件很慢」。

## Step 1: 先量化，再判断

```powershell
Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory | Select AvailableMBytes,CommittedBytes,CommitLimit,PagesPerSec
Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.IDProcess -ne 0 } |
  Sort-Object PercentProcessorTime -Descending | Select-Object -First 10 Name,IDProcess,PercentProcessorTime,WorkingSetPrivate
Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk | Select Name,PercentDiskTime,CurrentDiskQueueLength
```

**先拿数字**：内存只剩多少、提交量多少、磁盘队列多长。不要凭「感觉卡」下结论。

## Step 2: 分清三类瓶颈

| 瓶颈 | 判据 | 常见原因 |
|---|---|---|
| 内存不足 | AvailableMBytes 长期 < 1 GB，CommittedBytes 接近 CommitLimit | 浏览器标签、容器、虚拟机、泄漏进程 |
| 磁盘慢 | 队列长度长期 > 2，或系统盘是 HDD | HDD 做系统盘、索引重建、杀软全盘扫描 |
| CPU 打满 | 单进程长期 > 50% | 编译、录屏、异常进程 |

## Step 3: 处置原则

- 内存不足：先关占用大户，**不要先缩页面文件**（提交上限会更紧）
- 磁盘慢：确认是否 HDD；是则「换 SSD」是唯一根治
- 异常进程：查签名与路径，可疑时建议杀毒扫描，**不要直接结束系统进程**

## Step 4: 报告

给出「瓶颈类型 → 证据数字 → 建议」，并说明「换硬件」与「改配置」的分界。