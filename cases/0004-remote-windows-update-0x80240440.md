# 病例 0004：远端 Windows Update 反复报 0x80240440

> 状态：**诊断进行中**。已排除一个主要假设，其余待查。

## 1. 症状

- 远端笔记本 Windows Update 反复检查失败，事件里是 `0x80240440`
- 出现时间：2026-10-23 10:46、2026-10-24 06:15、06:16（连续两次）
- 用户感知：更新检查转圈/失败，但机器能正常上网

## 2. 环境

| 项 | 值 |
|---|---|
| 主机 | ustc-wjh / DESKTOP-CN7P93M |
| 系统 | Microsoft Windows 11 Pro，build 26300 |
| 是否管理员 | 是（探针回传 isAdmin=True） |
| 采集方式 | `remote --target ustc-wjh --set updates`（origin=remote:ustc-wjh） |
| 引擎版本 | v3.0.1 |

## 3. 采集（证据）

```powershell
winmedic.ps1 remote --target ustc-wjh --set updates
# 追加只读检查（远端）：
#   HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate  → NOPOLICY
#   ...\WindowsUpdate\AU                                    → NOAU
```

关键输出：

```
pendingReboot = True（原因：存在待重命名文件操作）
recentFailures: 0x80240440 @ 2026-10-24 06:16 / 06:15，2026-10-23 10:46
recentHotfixes: KB5127648 KB5127647 KB5121794 KB5127694（2026-10-20）、KB5124009（2026-09-23）
策略键: NOPOLICY / NOAU
```

## 4. 假设与排除

| 假设 | 判据 | 结果 |
|---|---|---|
| WSUS/策略指向了不可达的更新源 | 若有 WUServer + UseWUServer=1 且地址不通 | **排除**（NOPOLICY） |
| 存在待重启的文件重命名，阻断更新状态机 | 探针 `pendingReboot=True` | **支持**（尚不能确定是唯一原因） |
| Windows Update / Delivery Optimization 服务异常 | 需看服务状态与 `Get-WinEvent` 明细 | 待查 |
| 网络/代理拦截更新端 | 探针未发现代理启用；需验证到更新端点的连通性 | 待查 |
| 组件库损坏（CBS/WU 组件） | 需 `DISM /Online /Cleanup-Image /ScanHealth` | 待查（Tier 3，需计划） |

## 5. 处置（待定）

优先顺序（都不动系统文件）：

1. 安排重启（用户确认后）再复测更新检查
2. 若仍失败：查 WU/DO 服务状态与近期事件明细
3. 仍失败再考虑 `DISM /ScanHealth`（Tier 3，需显式计划 + 还原点）

## 6. 结果

未完成。已排除 WSUS 策略这一常见原因。

## 7. 教训

- `0x80240440` **不等于「没网」**：先看策略源，再看服务与待重启状态
- 待重启会污染更新状态机，**重启前不要下结论**
- 远端现场比猜测可靠：一条 `remote` 采集就拿到了事件明细、补丁清单与策略状态