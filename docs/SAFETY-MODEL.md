# 安全模型

## 四层防线

1. **分级（Tier 1–4）**：Tier 4 由引擎硬拒，不依赖提示词。
2. **plan 哈希绑定**：`apply` 重算哈希，与文件内记录比对，不一致退出码 5。
3. **隔离区软删除**：默认 `Move-Item` 到 `%ProgramData%\cdrive\quarantine\<runId>\<itemId>\`，只有 `--purge` 才真删。
4. **审计日志**：每条动作写 JSONL，含目标、前后可用空间、退出码、stdout 哈希。

5. **用户保留项**：`profile --exclude` 固化的路径在 plan 阶段排除、apply 阶段再次拦截（双层），命中即记账。

6. **风险门**：目标含 Tier 3（不可回滚）且恢复能力不是 `ready` 时，`apply` 直接拒绝（码 4），需先建还原点或显式 `--accept-risk`。
7. **standalone 白名单**：只有 catalog 里标注 `standalone: true` 且 Tier 1 的加性动作（当前仅建还原点）可脱离 plan 单独执行。

## 红线路径（引擎硬编码，规则表被改也拦得住）

```
\windows\winsxs
\windows\installer
\windows\system32
\windows\syswow64
\program files\windowsapps
\system volume information
\wechat files
\xwechat_files
\documents\tencent files
```

## 前置检查

| 检查 | 用途 |
|---|---|
| `admin` | 多数写操作需要管理员 |
| `services-stopped:...` | 清更新缓存前必须停 wuauserv/BITS/TrustedInstaller |
| `process-not-running:...` | 清浏览器/Office 缓存前必须关程序 |

前置不通过时该项被跳过并记账，**不允许绕过**。

## 跨卷限制

隔离区与目标必须在同一卷（`Move-Item` 才是原子元数据操作）。跨卷直接拒绝，避免「复制一半」的半成品状态。

## 不可回滚的动作

| 动作 | 原因 | 处置 |
|---|---|---|
| `storage.winsxs-cleanup` | 组件被真正删除 | Tier 3，逐项确认；明确告知不可逆 |
| `--purge` 清理 | 物理删除 | 默认关闭，需显式参数 |

## 诚实原则

- `pendingReboot` 为真时必须说明「重启后才生效」，不得谎报成功。
- 部分失败返回退出码 7，并提示可用 `restore` 回滚。