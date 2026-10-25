# 新机验收 / 体检基线

> **动手前先看 `plan` 的「已排除」小节**：被排除项要主动交代，被排除 ≠ 不该动。规则见 PB-001。


## 适用
「刚买的电脑帮我看看」「新机验收」「帮忙体检一下」。

## Step 1: 只读基线采集

```powershell
.\engine\winmedic.ps1 doctor
.\engine\winmedic.ps1 probe --set storage
Get-PhysicalDisk | Select FriendlyName,MediaType,HealthStatus,@{n='GB';e={[math]::Round($_.Size/1GB)}}
Get-BitLockerVolume | Select MountPoint,VolumeStatus,ProtectionStatus
Get-MpComputerStatus | Select AMServiceEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated
```

## Step 2: 必查项

| 项 | 正常基准 | 异常信号 |
|---|---|---|
| 系统盘类型 | SSD/NVMe | HDD（新机不该出现） |
| 可用空间 | > 40% | < 20% |
| 分区方案 | 单分区或 C >= 200 GB | C 只有 100 GB 且其他盘空着 |
| BitLocker | 与用户预期一致 | 开着但用户不知道密钥在哪 |
| Defender | 实时保护开 | 被第三方工具关掉 |
| 磁盘健康 | Healthy | Warning / 坏扇区 |

## Step 3: 出厂软件处理原则

**不主动卸载厂商预装软件**，只做「列出来 + 说明用途 + 由用户决定」。

## Step 4: 交付

输出一页体检报告：硬件 → 系统 → 存储 → 安全 → 建议项（按优先级）。
不夸大风险，不推销优化。