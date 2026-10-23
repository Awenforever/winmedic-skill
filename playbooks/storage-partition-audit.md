# 分区审计（是否该合盘/扩盘）

## 适用

「C 盘太小能不能扩」「要不要合盘」「D 盘空着 C 盘满了」。

## 原则：先劝退，再给方案

**合并分区是高风险操作，不是清理的替代品。** 默认建议是「迁移 + 清理」。

## Step 1: 只读取证

```powershell
Get-Partition | Select DiskNumber,PartitionNumber,DriveLetter,@{n='GB';e={[math]::Round($_.Size/1GB,2)}},Type
Get-Disk | Select Number,FriendlyName,PartitionStyle,@{n='GB';e={[math]::Round($_.Size/1GB)}}
Get-BitLockerVolume | Select MountPoint,VolumeStatus,ProtectionStatus
reagentc /info
```

必须确认：
1. 物理盘数量与容量（C 和 D 是否同一块盘）
2. **C 与 D 之间是否有恢复分区**（有则无法直接扩展）
3. **BitLocker 是否开启**（合并前必须解密，密钥丢失=数据报废）
4. 目标分区数据量与备份条件

## Step 2: 说清三条路的代价

| 方案 | 前置 | 耗时 | 风险 |
|---|---|---|---|
| 迁移 + 清理（推荐） | 无 | 30 分钟 | 极低 |
| 原生删分区扩 C | 外部备份 + 解密 + 禁 WinRE | 4–6 小时 | 中 |
| 第三方无损合并 | 解密 | 2–4 小时 | 中高 |

## Step 3: 若用户坚持合并

必须按顺序：
1. 备份目标分区数据到外部盘
2. 导出 BitLocker 恢复密钥
3. `manage-bde -off` 解密并等待完成
4. `reagentc /disable`
5. 删除中间分区与数据分区，扩展 C
6. `reagentc /enable` 重建 WinRE
7. 重新启用 BitLocker

**任何一步失败都可能需要重装。** 全程不得断电。

## Step 4: 路径问题的提醒

合并后 `D:\xxx` 全部失效。若必须保留路径，可给同一卷再挂 D: 盘符，并把原 D 盘内容恢复到卷根（注意同名目录冲突）。

## 结论口径

「你这台机器的问题不是垃圾多，是 C 盘给了 98 GB 而 D 盘空着 133 GB。清理能救急，但一年内还会满。」