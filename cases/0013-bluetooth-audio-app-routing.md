# 病例 0013：蓝牙耳机「系统提示音正常、应用媒体无声」

> 交接来源：用户提供的完整排查记录（2026-10-17 首次修复）+ 2026-10-30 只读复审。
>
> **重要**：§4 的「每应用路由」假设在 2026-10-30 晚被后续证据推翻；根因仍未定论。请务必先读 §9。

## 1. 症状

- 蓝牙耳机已连接，Windows 显示音频输出设备正常
- 视频/音乐开始可能正常，**暂停一段时间后恢复播放完全没有声音**
- 后期出现「刚连上就没声音」
- **Windows 调节音量时的提示音正常**，但应用媒体音频无声
- 不是系统主音量问题

关键区分：**提示音正常 + 应用无声 = 每应用音频路由/会话层问题**，不是蓝牙链路断开。

## 2. 环境

| 项 | 值 |
|---|---|
| 主机 | DESKTOP-CN7P93M（ustc-wjh），Windows 11 专业版 build 26300 |
| 蓝牙适配器 | BARROT Bluetooth 5.4，`USB\VID_33FA&PID_0010`，驱动 17.55.6.566 / `oem24.inf` |
| 耳机 | AirPlus Pro2（A2DP + HFP + AVRCP） |
| 干扰设备 | 同机还有 OPPO Enco Free2 的历史端点 |
| 对照实验 | 同适配器 + 同耳机在另一台电脑正常 → 排除硬件 |

## 3. 采集（历史 + 复审）

### 3.1 历史排查结论

- BARROT 适配器 `Status=OK`；A2DP / HFP / AVRCP 组件可枚举
- 曾**禁用 HFP** 想排除模式切换 → 无效，反而留下 `Status=Unknown` 的 Hands-Free 节点
- `Enable-PnpDevice` 对已不 Present 的节点返回「常规故障」
- 蓝牙服务（`bthserv`/`BTAGService`/`BthAvctpSvc`）历史均正常

### 3.2 2026-10-30 复审（只读）

| 项 | 结果 |
|---|---|
| 系统 | build 26300，Win11 专业版 |
| 驱动 | 17.55.6.566 / oem24.inf，**未变化** |
| 服务 | Audiosrv / AudioEndpointBuilder / bthserv / BTAGService / BthAvctpSvc 全部 Running |
| A2DP 端点 | `耳机 (AirPlus Pro2)` **Status=OK** |
| HFP | `AirPlus Pro2 Hands-Free`（MEDIA）**Status=Unknown**，其 AudioEndpoint 也 Unknown |
| 每应用路由 | `HKCU\...\Audio\PolicyConfig\PropertyStore` **19 个键** |
| 历史备份 | `Audio_AppRouting_Backup_20261017_172938.reg`，**301 个注册表键** |
| 历史日志 | 3/4 存在（Restore、Reset、Backup；`Bluetooth_Audio_Diagnostic_20261017_165852.txt` 缺失） |
| 系统事件 | 近 5 天无 Audio/Bth/Bluetooth 错误事件 |
| 虚拟音频 | NVIDIA HD Audio、NVIDIA Virtual Audio Device（正常） |

## 4. 假设与排除

| 假设 | 判据 | 结果 |
|---|---|---|
| 耳机/适配器硬件坏 | 同硬件在另一台电脑正常 | **排除** |
| 蓝牙链路断开 | 提示音正常、设备保持连接 | **排除** |
| 系统主音量/静音 | 提示音正常 | **排除** |
| HFP/A2DP 模式抢占 | 禁 HFP 后问题仍在 | **不支持**（但 HFP 现状被破坏） |
| 驱动问题 | 驱动版本未变、适配器 OK | **不支持**（无证据前不重装） |
| **每应用音频路由（PropertyStore）陈旧/错乱** | 重置该键 + 重启音频服务后恢复 | **支持**（组合修复有效，未做单变量） |

## 5. 处置（历史，已验证）

1. 导出 `HKCU\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore`
2. 重置该键下的应用音频路由
3. 重启 Windows Audio 服务
4. 重新播放并做长时间暂停恢复测试

结果：**恢复正常，长时间暂停后也不再无声**。

注意：这是「组合修复已验证」，不是「单变量根因已证明」。

## 6. 当前状态（2026-11-02）

- 症状已自行消失，用户确认「目前没有问题」，未做任何新改动
- **根因未定论**：路由假设已被推翻（见 §9），流/引擎/独占仍是候选
- HFP 仍是 Unknown 历史残留（用户若要用麦克风需单独验证）
- 默认输出设备无法在 SSH 会话内确认（session 0 无音频端点），需交互式验证

- 未收到复发报告；A2DP 端点 OK
- HFP 仍是 Unknown 历史残留（用户若要用麦克风需单独验证）
- 驱动未变；无相关系统错误
- **默认输出设备无法在 SSH 会话内确认**（session 0 无音频端点），需交互式验证

## 7. 教训

1. **提示音正常是重要分诊信号**：把问题从「蓝牙连接」拉到「应用音频会话」层
2. **禁用 HFP 是破坏性试验**：无效且留下 Unknown 节点；要先想清楚如何恢复
3. **组合修复要标注不确定性**：有效 ≠ 单变量证明
4. **远程排查音频有天然边界**：默认设备、实际播放、暂停恢复都必须在交互式会话验证

## 8. 对 winmedic 的意义（能力缺口，已于 v1.1.0 补齐）

v1.0.x 时 winmedic **没有音频/蓝牙域**（下表为当时状态）：

| 层 | 现状 |
|---|---|
| `catalog/probes.json` | 40 个探针，**0 个** audio/bluetooth |
| `catalog/actions.json` | 40 个动作，**0 个** audio |
| 诊断病例 | 6 个（磁盘/代理/缓存/崩溃日志/链路），无 `dx.bt-audio` |
| playbook | 无蓝牙音频条目 |

这次只能是**人工排查 + 病例沉淀**，引擎帮不上忙。

建议的补齐方向（按性价比）：

1. `probe --set audio`：端点状态（MMDevices Render/Capture）、默认设备（需交互式）、每应用 PropertyStore 键数、音频服务状态、虚拟声卡清单
2. `dx.bt-audio`：假设 × 指标（提示音是否正常、A2DP/HFP 端点状态、PropertyStore 陈旧键、驱动变更、事件日志）
3. playbook `PB-7xx bluetooth-audio-routing`：分诊顺序 + 安全边界（先只读、改注册表前备份）
4. 安全默认：**任何注册表/设备改动前强制导出备份**，与本案的 `.reg` 备份一致

## 9. 后续修正（2026-10-30 晚，推翻路由假设）

用户明确反对「连了新设备 ⇒ 路由问题」的解释，要求给出**单一根因**。复测证据如下：

| 证据 | 结果 | 含义 |
|---|---|---|
| 端点监控（25 分钟，2 秒采样） | 活跃端点集合**零切换**，AirPlus 始终 `state=1` | 设备没有掉线/重建 |
| 适配器电源状态 | 全程 `PD_MostRecentPowerState=1`，即 **D0**（此前误读为 D1） | 电源管理排除 |
| 音频运维日志 | 无声时段**没有**设备状态变更事件 | 不是设备层 |
| 每应用路由 | 绿联播放器**没有**任何 PropertyStore 条目 | 路由假设不成立 |
| 对照应用 | 17:58 Edge 同样无声 | 不是单一应用问题 |

结论修正：

- §4/§5 的「重置 PropertyStore」**不是已证明的根因修复**；2026-10-17 的有效性更可能来自**重启 Audiosrv**
- 目前最可能的层级是**音频流/引擎**（含独占模式争抢这一未验证分支），但**没有单变量证据**
- 症状后来自行消失，未能复现，**根因保持 open**；不复现就不改系统

方法论教训（已沉淀为病例 0015）：

1. 原始值不是事实：`CM_POWER_DATA` 的 `1` 是 D0，不是 D1
2. 过滤器本身就是假设：按名称筛端点会漏掉新端点，应先输出全集
3. 不要用采集结果否定用户的第一手观察，先怀疑采集口径

## 10. 引擎补齐结果（v1.1.0）

| 能力 | 状态 |
|---|---|
| `probe --set audio` | ✅ 端点状态（解码）、每应用路由（`stale`/`orphan` 分离）、服务、HFP、虚拟声卡 |
| `diagnose --case dx.bt-audio` | ✅ 链路 / 路由 / 引擎 / HFP / 历史残留 五类假设 |
| `PB-704 bluetooth-audio-routing` | ✅ 分诊顺序 + 改注册表前强制导出 |
| 语义解码 | ✅ `catalog/enums.json` + `Audio.Tests` |
