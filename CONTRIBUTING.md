# 贡献指南

## 提交前

```powershell
.\scripts\validate-catalog.ps1      # catalog 三张表与 schema
Invoke-Pester .\tests\pester         # 单元测试
Invoke-Pester .\tests\routing        # 路由测试
```

## 新增一个领域，需要改哪些文件

1. `catalog/probes.json` —— 注册探针（含 `impl` 指向实现）
2. `engine/probes/<domain>.ps1` —— 实现探针函数，**只读**
3. `catalog/evidence.json` —— 每个新动作必须先有证据条目
4. `catalog/actions.json` —— 动作定义（`tier` / `rollback` / `verify` 必填）
5. `playbooks/<domain>-*.md` —— 判断流程（**不得写具体命令**）
6. `playbook-index.md` —— 加路由行
7. `tests/pester` 与 `tests/routing` —— 至少各加一条

## 硬性规则

- 新增动作**必须**有 `evidence` 条目，含官方链接与 `verifiedOn`；无官方文档的标 `strength: empirical` 并写清实测环境。
- Playbook 里**禁止**出现 `Remove-Item`、`del`、`rd` 等命令——命令只能存在于 catalog。
- 脚本输出**禁止 emoji**（GBK 控制台会乱码）。
- PowerShell 代码必须兼容 5.1，且不依赖 @` 反引号转义。

## 提交信息

Conventional Commits：`feat(engine):`、`fix(probe):`、`docs(safety):`、`test(routing):`