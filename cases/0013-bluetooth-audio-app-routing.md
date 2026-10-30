# 病例 0013：蓝牙耳机「系统提示音正常、应用媒体无声」

> 交接来源：用户提供的完整排查记录（2026-10-17 首次修复）+ 2026-10-30 只读复审。

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

## 6. 当前状态（2026-10-30）

- 未收到复发报告；A2DP 端点 OK
- HFP 仍是 Unknown 历史残留（用户若要用麦克风需单独验证）
- 驱动未变；无相关系统错误
- **默认输出设备无法在 SSH 会话内确认**（session 0 无音频端点），需交互式验证

## 7. 教训

1. **提示音正常是重要分诊信号**：把问题从「蓝牙连接」拉到「应用音频会话」层
2. **禁用 HFP 是破坏性试验**：无效且留下 Unknown 节点；要先想清楚如何恢复
3. **组合修复要标注不确定性**：有效 ≠ 单变量证明
4. **远程排查音频有天然边界**：默认设备、实际播放、暂停恢复都必须在交互式会话验证

## 8. 对 winmedic 的意义（能力缺口）

当前 winmedic（v1.0.x）**没有音频/蓝牙域**：

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
