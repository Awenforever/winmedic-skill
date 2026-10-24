# WinMedic MCP 服务器

> 给不支持「读 SKILL.md + 跑脚本」的宿主（Claude Desktop 等 MCP 客户端）用。

## 它是什么

一个 **stdio JSON-RPC 2.0** 服务器，PowerShell 5.1 实现，零依赖。
它不重新实现任何逻辑，所有工具调用都转成 `engine\winmedic.ps1` 的子命令——
**隔离区、plan 哈希、红线、风险门、审计日志全部照旧生效**。

## 启动

```powershell
.\engine\mcp\winmedic-mcp.ps1              # 全功能
.\engine\mcp\winmedic-mcp.ps1 -ReadOnly    # 只读审查模式（禁用 apply / restore / profile 写入）
```

stdout 只输出 JSON-RPC；日志走 stderr。

## 客户端配置（Claude Desktop 示例）

```json
{
  "mcpServers": {
    "winmedic": {
      "command": "powershell",
      "args": [
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "C:\\tools\\winmedic-skill\\engine\\mcp\\winmedic-mcp.ps1"
      ]
    }
  }
}
```

只读模式把 `-ReadOnly` 加到 args 末尾即可。

## 工具清单

| 工具 | 写操作 | 说明 |
|---|---|---|
| `winmedic_doctor` | 否 | 环境自检 |
| `winmedic_probe` | 否 | 只读采集（set 可选 11 个探针集） |
| `winmedic_summary` | 否 | 九域摘要 + 建议 |
| `winmedic_plan` | 否 | 方案 + 证据 + planHash |
| `winmedic_apply` | **是** | 必须 `yes=true`，且给 `ids` 或 `action` |
| `winmedic_verify` | 否 | 复核某次执行 |
| `winmedic_restore` | **是** | 必须 `yes=true` |
| `winmedic_journal` | 否 | 审计批次列表 |
| `winmedic_explain` | 否 | 动作证据与回滚方式 |
| `winmedic_profile` | 部分 | 无参数只读；带 `exclude` 才写 |

## 安全边界

1. **双重开关**：写工具要求 `yes=true`，缺省拒绝（返回 `isError: true` 并说明原因）。
2. **只读模式**：`-ReadOnly` 下写工具直接拒绝，适合「只看不动」的场景。
3. **不绕过引擎**：服务器不拼命令，只转发子命令；因此红线、风险门、plan 校验全部继承。
4. **权限不变**：`apply` 仍要求管理员；非管理员返回引擎的退出码 3，包成 `isError: true`。

## 协议细节

- `initialize` → 返回 `protocolVersion: 2024-11-05`、`capabilities.tools`、`serverInfo`
- `tools/list` → 10 个工具及 JSON Schema
- `tools/call` → `{ content: [{type:'text', text}], isError }`
- 未知方法 → `-32601`；未知工具/缺参数 → `-32602`
- 通知（无 `id`）不返回响应

## 已知限制

- 每个工具调用都会起一个 `powershell -File` 子进程，延迟约 0.6–1.5 秒（探针更久）
- `apply` 的长时间操作（如 DISM）可能超过客户端超时，建议拆成 `apply --action` 单步执行
- 服务器是无状态的：不缓存 findings，每次都读磁盘上的 `state\*.json`