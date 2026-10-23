# 证据契约

每条动作**必须**关联一个 evidence 条目，否则 `validate-catalog.ps1` 直接失败。

## 强度分级

| strength | 含义 | 要求 |
|---|---|---|
| `official` | 有微软/厂商官方文档明确说明 | 必须有 `links` 与 `quote` |
| `indirect` | 官方文档间接提及，或需组合推断 | 必须有 `links` |
| `empirical` | 无官方文档，依据实测 | 必须在 `notes` 写清实测环境与结论 |

## 必备字段

```json
{
  "id": "ev.example",
  "strength": "official",
  "links": ["https://learn.microsoft.com/..."],
  "quote": "原文关键句",
  "verifiedOn": "2026-10-23",
  "notes": "适用条件、副作用、常见误判"
}
```

## 复核周期

`verifiedOn` 超过 **180 天** 时，CI 会提示需要复核（未来版本将升级为告警）。

## 反面教材

- 把「业界惯例」写成 `official` —— 不允许
- 只贴链接不写原文 —— 不允许（链接会失效）
- 无 `verifiedOn` —— 不允许