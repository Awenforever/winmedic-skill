# PB-603 U 盘快捷方式蠕虫处置

> 症状：U 盘根目录出现 `.lnk`、文件夹「消失」、多出隐藏目录；或插入后杀软报警。
> 原则：**先还原数据，再清除入口，最后找感染源**。不要双击盘内任何图标。

## 只读判定

```powershell
winmedic.ps1 probe --set usb
winmedic.ps1 diagnose --case dx.usb-worm
```

判读：`level=infected` 表示有可疑快捷方式/载荷/非打印隐藏目录；`hiddenDataItems>0` 表示有数据被藏。

## 处置顺序

1. **不要执行**盘上的 `.lnk`，也不要双击文件夹图标；从导航栏点盘符进入
2. 把 `.lnk` 复制到隔离区并记录 SHA256（`C:\ProgramData\winmedic-quarantine\<日期>-usb-<盘符>\`）
3. 把隐藏目录里的数据**同盘移动**回根目录；同名冲突移到 `_recovered_<日期>`，不覆盖
4. 载荷（`DrvSvc*`/`*Mgrsvr*`）不要直接拷出样本；交给安全软件隔离区取哈希，或仅记录存在与大小
5. 删除快捷方式、载荷与空隐藏目录
6. 主机痕迹三件套：Prefetch（`DRVSVC*`）、Run/RunOnce、服务/计划任务
7. 找感染源：同一支盘反复中招，说明另一台机器仍在写盘

## 伪卷目录要解第二层

蠕虫常把用户数据挪进一个**冒充卷标**的目录，例如 `Usb Drivе`——注意末尾是西里尔 `е`（U+0435），肉眼几乎看不出。

还原隐藏目录之后，这个伪卷会跟着搬到根目录，**看起来盘已经干净了，其实数据还套在里面一层**。必须再解一层：

1. `probe --set usb` 看 `fakeVolumes`（新增字段）：`confusable-script` 表示同形字伪装
2. 把伪卷里的内容**同盘移动**到根目录；同名冲突加后缀（如 `HPSCANS` → `HPSCANS_fromUsbDrive`），**绝不覆盖**
3. 确认伪卷内 0 项后删除空壳
4. 若合并了同名目录，在目录内留一份 `合并记录_*.txt` 写清改名映射与哈希

## 删不掉的空隐藏目录（U+FFFF）

单字符隐藏目录（U+FFFF 之类）一旦内容被清空，`Get-ChildItem -LiteralPath` 会抛「系统找不到指定的文件」（ERROR_FILE_NOT_FOUND），删除也会失败。改用 .NET：

```powershell
[IO.Directory]::Delete($dirFullPath, $true)
```

删除前先确认空：`[IO.Directory]::GetFileSystemEntries($dirFullPath).Length -eq 0`。

## 识别安全软件的诱饵目录

根目录出现隐藏、系统属性、删不掉的目录时，先看它是不是联接：

    Get-Item 'F:\ZSTORE995' -Force | Select-Object Name,LinkType,Target,Attributes

若 Target 指向 Huorong\Sysdiag\BaitRoot 之类，是勒索诱饵，不是病毒，不要删。

## 安全边界

- 不关闭杀软、不改防护策略来「取样」
- 不删除用户数据；隐藏目录里的内容先还原
- 不同盘之间复制大文件前先看剩余空间；同盘移动不占空间

## 验证

- 根目录无 `.lnk`、无隐藏目录、无载荷名文件
- 数据抽样可读，数量与隐藏目录内一致
- 主机 Prefetch/Run/服务/计划任务无相关项

## 关联

- 病例 `cases/0012-usb-shortcut-worm.md`
