# 已知局限（发布前必读）

> 这份文档存在的目的：**不让使用者对能力产生错误预期**。

## 1. 动作验证覆盖：24 / 40

40 个处置动作里，**24 个**做过真机 `apply → restore` 且逐字节一致（清单见 `docs/VERIFIED-TARGETS.md`）。

| 状态 | 数量 | 说明 |
|---|---:|---|
| 已验证 | 24 | 移动 + 还原 + 哈希一致 |
| 未验证 | 16 | 多为依赖特定软件（Slack/Adobe/HF）或不可逆动作 |

未验证 ≠ 不能用；但第一次使用时应**先在非关键目录上试**。

## 2. 不可回滚的动作

| 动作 | 为什么不可回滚 |
|---|---|
| `storage.hiberfil-off` | `powercfg /h off` 直接删除休眠文件，再开启只会生成空文件 |
| `storage.winsxs-cleanup` | DISM 组件清理不可逆 |

这两个动作会要求单独确认；`restore` 对它们无效。

## 3. 远端能力有前提

- `remote`（只读采集）需要目标机可通过 ssh 免密访问，且**会在目标机临时解压引擎包**
- `remote-probe --set net-link` 是**零落盘**的只读体检（推荐用于别人的机器）
- `remote-apply` 需要本地计划明确带 `origin=remote:<别名>`，远端引擎需 `--allow-remote-origin`
- 远端隔离区在 `C:\ProgramData\winmedic-remote-state`，**不会**随暂存目录清理

## 4. 平台与权限

- 只在 **Windows 11 + PowerShell 5.1** 上验证过；Windows 10 未做完整回归
- `apply` / `restore` 需要管理员；`probe` / `plan` / `trend` / `diagnose` 普通用户可跑
- 状态目录默认 `C:\ProgramData\cdrive`，不可写时回退到 `%LOCALAPPDATA%\winmedic`

## 5. 安全软件干扰（真实踩过）

火绒等国产杀软可能**按内容拦截** `engine/lib/Remote.ps1`（表现为读取为空/文件消失）。

- `doctor` 会检查引擎文件完整性并在缺失时提示
- 处理：把**仓库目录**加入信任区（不要只加单个文件或 Temp 路径），再 `git checkout -- engine/lib/Remote.ps1`
- 受影响时远端功能不可用，其余功能不受影响

### 实测记录（2026-10-26，win11-test VM）

VM 上的火绒（HipsDaemon）拦截了 `Remote.ps1` 的复制。安装脚本**继续完成安装**并打印：

```
注意：engine/lib/Remote.ps1 缺失或被安全软件拦截（读到的内容为空）。
  - 远端功能（remote / remote-probe / remote-apply）将不可用，其它功能正常
```

安装后 `probe` / `plan` / `selftest` 均正常；`remote-probe` 返回退出码 4 并提示加入信任区。

## 6. 趋势需要时间

`trend` 的速率（perDay）在跨度 < 0.5 天时会拒绝给出，这是刻意的。要看到真实增长，至少积累一天。

## 7. 其它

- 文档与输出以中文为主，英文文档仅 `README.en.md`
- 没有安装器/自动更新；分发形式是 zip + 校验和
- 不联网、不上报、无遥测
