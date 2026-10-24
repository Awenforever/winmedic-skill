# 病例 0008：新清理目标一执行就抛 `LiteralPath 为空`

## 1. 症状

- 对新增目标（CBS 日志 / pip 缓存 / Chrome 着色器缓存）执行 `apply` 时报错：
  `Invoke-VerifyRule : 无法将参数绑定到参数“LiteralPath”，因为该参数是空值。`
- 文件其实已经被移走，但执行被判失败

## 2. 环境

| 项 | 值 |
|---|---|
| 主机 | win11-test VM（管理员） |
| 引擎 | v3.5.1 |

## 3. 采集（证据）

```
catalog/actions.json: "verify": { "kind": "path_absent" }   ← 只有 kind，没有 path
Verify.ps1: path_absent 使用 $Rule.path
winmedic.ps1: Invoke-ActionVerify -Action $act   ← 没把 item 传进去
```

## 4. 假设与排除

| 假设 | 判据 | 结果 |
|---|---|---|
| 目录权限问题 | 同机其它目标可移走 | 排除 |
| catalog 里 verify 规则写错 | 规则只有 kind，目标路径应由 plan item 提供 | **支持** |

## 5. 处置

| 动作 | 影响面 | 可回滚 |
|---|---|---|
| `Invoke-ActionVerify -Item` + `Invoke-VerifyRule -FallbackPath` | 所有 path_absent 动作 | — |
| 无路径时返回「跳过校验」而非崩溃 | 防御性 | — |

## 6. 结果

- 是否解决：是。三目标批量验证 3/3 通过（移走=True 还原=True 哈希一致=True）

## 7. 教训

- 新增「同构动作」时，要检查**共用校验逻辑**是否需要新的上下文（这里需要 item.target）
- 批量验证比单点验证更容易暴露这类问题：一个目标过了，不代表同 kind 的其它目标也过