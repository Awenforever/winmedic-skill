# BitLocker 恢复分诊

## 适用
「开机要恢复密钥」「换了主板/硬盘后进不去」「BitLocker 提示恢复」。

> 这是**数据安全场景**，不是清理场景。宁可慢，不可错。

## Step 1: 先确认这是什么

| 现象 | 含义 |
|---|---|
| 开机蓝色恢复界面，要求 48 位密钥 | 正常恢复流程，需要密钥 |
| 输入正确密钥后仍循环 | TPM 状态异常，需挂起/重建保护器 |
| 磁盘在别的机器上锁住 | 需该盘的恢复密钥 |

## Step 2: 找密钥（按优先级）

1. **Microsoft 账户**：https://account.microsoft.com/devices/recoverykey
2. 组织的 Azure AD / Intune（公司电脑）
3. 打印/保存的纸质或文本备份
4. `manage-bde -protectors -get C:`（**能进系统时才有用**）

**没有密钥 = 数据无法恢复。** 不要尝试「暴力破解」或所谓解密工具。

## Step 3: 只在能进系统时才做的检查

```powershell
manage-bde -status
Get-BitLockerVolume | Select MountPoint,VolumeStatus,ProtectionStatus,KeyProtector
Confirm-SecureBootUEFI
```

## Step 4: 常见修复

| 情况 | 处置 |
|---|---|
| 固件更新后触发恢复 | 输入密钥进入 → `manage-bde -protectors -disable C: -rebootcount 2`，重启后自动重新启用 |
| TPM 需重新封装 | 进系统后 `manage-bde -protectors -delete C: -type TPM` 再 `-add` |
| 换主板 | 必须先解密再换，或提前备份密钥 |

## 红线

- 不在没有密钥的情况下格式化
- 不用第三方「BitLocker 破解」工具
- 不把恢复密钥贴到聊天记录或工单里（除非走安全通道）

## Step 5: 报告

明确回答：**有没有密钥 / 能不能进系统 / 下一步是恢复还是重装**。