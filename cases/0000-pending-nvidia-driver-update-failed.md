# 病例（待补证据）：远端 NVIDIA 驱动更新失败

> **状态：未完成。** 目标机 `192.168.0.103` 当时离线，尚未采集现场证据。
> 本文件保留为**待执行的调查计划**，不得据此下任何结论。

## 1. 症状（用户报告，未验证）

- 用户原话：「远端 PC 的 nvidia 更新失败」
- 待确认：是 NVIDIA App 更新失败，还是 Windows Update 推的驱动失败

## 2. 环境（待填）

| 项 | 值 |
|---|---|
| 主机 | 192.168.0.103 / LAPTOP-TC3FKDD7 |
| 采集方式 | `remote --target augenstern-adm --set updates` |

## 3. 采集计划（证据）

```powershell
winmedic.ps1 remote --target augenstern-adm --set updates --keep
# 远端补充（由 Agent 显式执行，引擎不联网）：
#   事件日志: wevtutil qe System /c:50 /rd:true /f:text
#   驱动包:   pnputil /enum-drivers
#   安装日志: C:\ProgramData\NVIDIA Corporation\Installer2\*.log
#   磁盘余量: 驱动解压需要数 GB 临时空间
```

## 4. 待验证的假设（按概率排序）

| 假设 | 判据 |
|---|---|
| 临时空间不足 | C: 剩余 < 5 GB，安装器日志报 disk full |
| 旧驱动残留/冲突 | `pnputil /enum-drivers` 有多个同名不同版本 |
| Windows Update 与 NVIDIA App 冲突 | 事件日志有 0x80070103 之类代码 |
| 权限/服务问题 | NVIDIA 服务未启动，安装器日志报 access denied |
| 与安全软件冲突 | 火绒/Defender 拦截记录 |

## 5. 处置（待定，需先确认假设）

## 6. 结果

待填。

## 7. 教训（暂时只有一条）

- **没有现场证据就不要写结论**：本病例刻意保留为「待补」，而不是编一个像样的故事。