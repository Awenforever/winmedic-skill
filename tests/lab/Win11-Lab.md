# 真机验收记录模板

> 每台机器复制一份，完成后归档到 docs/FIELD-NOTES.md 的对应代号下。

## 基本信息

| 项 | 值 |
|---|---|
| 代号 | |
| 系统版本 | |
| PowerShell | |
| 是否管理员 | |
| WizTree | 有 / 无 |

## 执行记录

| 步骤 | 命令 | 结果 | 备注 |
|---|---|---|---|
| doctor | `winmedic.ps1 doctor` | | |
| probe | `probe --set storage` | 候选 N 项 / X GB | |
| plan | `plan` | 哈希 | |
| apply | `apply --ids R? --yes` | runId | 选了哪项、为什么 |
| verify | `verify --journal ` | 可用空间变化 | |
| restore | `restore --journal ` | 是否成功恢复 | **必须做** |

## 验证点

- [ ] restore 后目标目录/文件回到原位置
- [ ] 相关程序仍能正常启动
- [ ] journal 记录完整（含 before/after 大小）
- [ ] 无残留隔离区垃圾（purge 前确认）
