# WinMedic

> A Windows computer-repair skill for AI agents — **read-only first, reversible by default, evidence-backed.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

WinMedic is a skill package that lets an AI agent diagnose and fix Windows problems. It splits responsibilities: the **model makes judgments**, a **zero-dependency deterministic engine performs actions**.

## How it differs

| | Typical skills | WinMedic |
|---|---|---|
| Execution | Playbooks describe "semantic tools"; the agent composes commands | Engine exposes fixed actions; **the agent passes ids, never commands** |
| Rollback | "Please confirm first" in prose | **Quarantine + journal + restore** — destructive steps are reversible |
| Evidence | Reasoning in prose | Every action carries **official link + quote + verification date**; CI fails without it |
| Tests | None | Pester unit tests + 14 engine hard cases + routing tests + CLI contract tests |

In one sentence: **other skills tell you how to repair; WinMedic guarantees the repair is correct, undoable, and justified.**

## Quick start

```powershell
# 1. Environment check (read-only)
.\engine\winmedic.ps1 doctor

# 2. Collect facts (read-only). Falls back gracefully when WizTree is absent.
.\engine\winmedic.ps1 probe --set storage

# 3. Build a plan (read-only)
.\engine\winmedic.ps1 plan

# 4. Execute (requires --yes; moves to quarantine instead of deleting)
.\engine\winmedic.ps1 apply --plan state\plan.json --ids R1,R2 --yes

# 5. Verify or roll back
.\engine\winmedic.ps1 verify --journal <runId>
.\engine\winmedic.ps1 restore --journal <runId>
```

## Commands

| Command | Purpose | Writes? |
|---|---|---|
| `doctor` | Environment self-check (OS, PowerShell, admin, WizTree) | No |
| `probe --set <storage|boot|apps|updates|network|security|recovery|printers|backup|intake|all>` | Collect facts | No |
| `summary` | Nine-domain health screen | No |
| `plan` | Grade candidates, attach evidence, compute plan hash | No |
| `apply` | Execute selected items (quarantine by default) | **Yes** |
| `verify` / `restore` | Check effect / roll back | verify: no, restore: **yes** |
| `journal` | Audit trail | No |
| `profile --exclude <pattern>` | Persist user keep-list (double-layer enforcement) | Yes |
| `report` | Five-section delivery report | No |
| `explain --action <id>` | Show evidence, cautions, rollback for an action | No |
| `diff --from a.json --to b.json` | Compare two collections | No |

## Safety model

- **Read-only first**: `doctor`, `probe`, `plan`, `summary`, `verify`, `explain`, `report`, `diff` never write.
- **Plan hash binding**: `apply` recomputes the plan hash; a modified plan is rejected (exit 5).
- **Quarantine by default**: items are moved to `%ProgramData%\cdrive\quarantine\`, only `--purge` really deletes.
- **Red lines are hard-coded**: WinSxS internals, `Windows\Installer`, `System32`, `WindowsApps`, chat-data folders are refused by the engine, not by prompt.
- **Risk gate**: if a target is Tier 3 (irreversible) and recovery readiness is not `ready`, `apply` refuses (exit 4).
- **User keep-list**: `profile --exclude` is enforced in both `plan` and `apply`.
- **Non-admin degradation**: non-admin sessions can only read; `apply` returns exit 3.

Exit codes: `0` success · `2` usage · `3` permission · `4` precondition · `5` plan invalid · `6` red line · `7` partial (rollback available).

See [docs/SAFETY-MODEL.md](docs/SAFETY-MODEL.md) (Chinese) for the full model.

## Layout

```
SKILL.md             routing + mandatory workflow (read by the agent)
playbook-index.md    symptom -> playbook routing table
playbooks/*.md       per-domain judgment procedures (lazy-loaded)
engine/              deterministic engine (Windows PowerShell 5.1, no dependencies)
catalog/             machine-readable probes / actions / evidence
tests/               Pester unit tests, routing tests, CLI contract, lab template
docs/                design, safety model, evidence contract, hard cases, roadmap
```

## Domains covered

Storage · Boot & performance · Applications · Updates & drivers · Network · Security posture · Recovery · Printers · Backup · New-device intake

21 playbooks, 36 probes, 13 actions, 14 evidence entries.

## Requirements

- Windows 10 / 11
- **Windows PowerShell 5.1** (built in; PowerShell 7 is not required)
- Optional: WizTree (faster scans; falls back to targeted measurement)

The engine makes **no network requests** and collects **no telemetry**.

## Documentation

- [QUICKSTART (English)](docs/en/QUICKSTART.md)
- [设计说明 (Chinese)](docs/DESIGN.md) · [安全模型](docs/SAFETY-MODEL.md) · [证据契约](docs/EVIDENCE-CONTRACT.md)
- [难例清单](docs/HARD-CASES.md) · [路线图](docs/ROADMAP.md) · [真机记录](docs/FIELD-NOTES.md)

## License

[MIT](LICENSE)