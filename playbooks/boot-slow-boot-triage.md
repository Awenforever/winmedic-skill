# 开机慢分诊

## 适用
「开机很慢」「开机卡在登录界面」「开机要等好几分钟」。

## Step 1: 区分「真慢」还是「感觉慢」

只读取证：
```powershell
(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 5 |
  Select TimeCreated,Id,@{n='Ms';e={$_.Properties[0].Value}} | Format-Table
```

事件 ID 100 = 启动耗时。**先拿到数字再下结论。**

## Step 2: 查三个常见病因

| 病因 | 取证 | 处理 |
|---|---|---|
| 启动项过多 | 任务管理器「启动」页 / `Get-CimInstance Win32_StartupCommand` | 禁用非必要项（可逆） |
| 快速启动异常 | `HiberbootEnabled` = 0 却报告开机慢 | 视情况开启/关闭，需说明代价 |
| 磁盘慢 | 系统盘是否 HDD / 磁盘队列长 | 换 SSD 是唯一根治 |

## Step 3: 红线

- 不要为了「开机快」删系统服务
- 不要盲目关 Defender
- 不要用第三方「优化大师」类工具

## Step 4: 报告

给出「启动耗时基线 → 主要耗时环节 → 建议动作（可逆优先）」。