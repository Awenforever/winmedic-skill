# PB-704 蓝牙音频：提示音正常而应用无声

> 症状：耳机已连接、系统提示音正常，但视频/音乐无声；或暂停后恢复无声；或只有某些应用无声。
> 原则：**先分层证明问题在哪一层**，不要先禁用 HFP，也不要重装蓝牙驱动。

## 分层模型

按顺序逐层验证，前一层不成立就不要看后一层：

```
1 设备层  端点是否 ACTIVE、适配器是否 OK
2 路由层  每应用路由是否指向已断开的设备
3 引擎层  Audiosrv / AudioEndpointBuilder / audiodg
4 独占层  是否有应用占着独占模式
5 应用层  只有单个应用无声
6 链路层  A2DP/HFP 抢占、耳机空闲休眠
```

## 只读采集

```powershell
winmedic.ps1 probe --set audio
winmedic.ps1 diagnose --case dx.bt-audio
```

判读三组事实：蓝牙活跃端点数、陈旧应用路由数、音频/蓝牙服务状态。

## 判读表

| 事实 | 指向 |
|---|---|
| `btActive = 0` | 设备/连接层：配对、适配器、耳机休眠 |
| `staleRoutes > 0` | 路由层：应用被固定在旧设备上 |
| `servicesOk = 0` | 引擎层：音频服务未运行 |
| `hfpNotOk > 0` | HFP 残留节点（不要批量禁用） |
| 三项都正常 | 独占或应用层：退出播放器后用另一个应用对照 |

## 安全边界

- 改注册表前先导出：

```powershell
reg export "HKCU\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore" "D:\Audio_PropertyStore_Backup_<时间>.reg" /y
```

- **不要**批量禁用 Hands-Free，也不要删除所有蓝牙 PnP 设备
- **不要**在没有驱动版本差异证据时卸载蓝牙驱动
- 默认音频设备需要在交互式桌面确认；SSH/服务会话取不到
- 只删指向**非活跃设备**的应用路由，保留指向当前设备的条目

## 修复顺序（风险从低到高）

1. 应用音量与输出设备
2. 清理陈旧的应用路由（先备份）
3. 重启 Audiosrv（会中断音频 2–3 秒）
4. 检查 A2DP/HFP 端点映射
5. 最后才考虑驱动或设备重装

## 验证

- 连接后立即播放有声
- 暂停 5 分钟后恢复有声
- 切换播放器/浏览器仍正常
- 断开蓝牙并重连后正常
- 系统提示音与媒体声音都正常
- 如需通话，再单独验证麦克风与免提

## 关联

- 病例 `cases/0013-bluetooth-audio-app-routing.md`
