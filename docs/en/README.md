# English documentation

- [QUICKSTART.md](QUICKSTART.md) — install, first run, plan/apply/rollback, exit codes
- [../../README.en.md](../../README.en.md) — project overview

Design documents are currently Chinese-only (`docs/DESIGN.md`, `docs/SAFETY-MODEL.md`, `docs/EVIDENCE-CONTRACT.md`, `docs/HARD-CASES.md`). Translation is tracked in the roadmap.

## Glossary (for reading the Chinese docs)

| Chinese | English |
|---|---|
| 探针 | probe (read-only collector) |
| 动作 | action (guarded mutation) |
| 方案 | plan (graded, evidence-attached, hashed) |
| 隔离区 | quarantine (soft-delete area) |
| 审计日志 | journal (JSONL audit trail) |
| 证据 | evidence (official link + quote + date) |
| 保留项 | user keep-list / exclusion |
| 风险门 | risk gate |
| 红线 | red line (hard refusal) |
| 前置检查 | precondition |
| 还原点 | restore point |
| 卷影副本 | shadow copy |