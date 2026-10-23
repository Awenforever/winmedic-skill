# 启动失败分诊

## 适用
「蓝屏进不去系统」「一直转圈」「自动修复失败」「开机黑屏」。

> 进不去系统时，Agent 通常也没有执行环境。**先给出离线操作路径，不要假装能远程修。**

## Step 1: 先分类

| 现象 | 可能原因 | 走向 |
|---|---|---|
| 能进 BIOS，卡在 Windows 徽标 | 驱动/更新损坏 | WinRE 启动修复 |
| 蓝屏有错误码 | 驱动/内存/磁盘 | 记录错误码再判断 |
| 自动修复循环 | 引导记录/系统文件损坏 | WinRE 命令行 |
| 完全黑屏无 BIOS | 硬件 | 硬件检测，不是软件问题 |
| 提示 BitLocker 恢复 | TPM/固件变更 | 见 PB-602 |

## Step 2: 进 WinRE 的方式

1. 开机连按 F8（部分机型无效）
2. 强制断电三次，第四次会自动进入恢复环境
3. U 盘启动介质（最可靠）

## Step 3: WinRE 里的修复顺序

```
bootrec /fixmbr
bootrec /fixboot
bootrec /scanos
bootrec /rebuildbcd
sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows
dism /image:C:\ /cleanup-image /restorehealth
```

**从破坏性最小的开始**：先 `sfc`，再 `dism`，最后才动 bootrec。

## Step 4: 能用系统时的事后分析

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,1001,6008} -MaxEvents 10
Get-CimInstance Win32_ReliabilityRecords -ErrorAction SilentlyContinue | Select-Object -First 10
```

蓝屏错误码记下来再查，不要凭印象说是内存问题。

## Step 5: 数据优先

如果修复成本高，**先保数据**：把盘挂到别的机器上拷出重要文件，再考虑重装。

## 红线

- 不盲目 `diskpart clean`（会清空分区表）
- 不在没备份时重装
- 不建议用户「先格式化试试」