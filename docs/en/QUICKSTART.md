# WinMedic — English quick start

## 1. Where to install

Copy the repository into your agent's skill directory. WinMedic is a single-folder skill:

```
~/.dsh/skills/winmedic/        (DeepSeek Harness)
or any folder your agent can read SKILL.md from.
```

The agent reads `SKILL.md` for routing and invokes `engine\winmedic.ps1` for execution.

## 2. First run (read-only)

```powershell
cd <repo>
.\engine\winmedic.ps1 doctor                 # environment
.\engine\winmedic.ps1 probe --set intake     # cross-domain facts, ~40-90s
.\engine\winmedic.ps1 summary                # nine-domain health screen
```

NaN

```
[OK]   磁盘  C: 可用 30.7 GB / 98.7 GB（已用 68.9%）
[OK]   启动  启动项 21 个（可禁用 5）；性能 ok
[WARN] 更新  待重启 是；问题设备 0
[WARN] 安全  裁决 attention
[BAD]  恢复  等级 poor（没有系统还原点；没有卷影副本）
```

Output is Chinese in v1 (the engine targets Chinese Windows). The JSON artefacts (`state\*.json`) are language-neutral.

## 3. Plan and execute

```powershell
.\engine\winmedic.ps1 plan                              # writes state\plan.json + plan.md
Get-Content .\state\plan.md                            # show it to the user verbatim
.\engine\winmedic.ps1 apply --plan .\state\plan.json --ids R1,R3 --yes
.\engine\winmedic.ps1 verify --journal <runId>
.\engine\winmedic.ps1 restore --journal <runId>          # if anything looks wrong
```

Rules:

- Never invent ids — only ids present in `plan.json`.
- Never add `--purge` unless the user explicitly asks for permanent deletion.
- If `verify` reports `pendingReboot`, say so; do not claim full success.

## 4. Keep-list

```powershell
.\engine\winmedic.ps1 profile --exclude "C:\Users\<user>\Documents\WeChat Files"
.\engine\winmedic.ps1 profile --exclude "D:\*"
.\engine\winmedic.ps1 profile                # list current rules
```

Exclusions are enforced twice: filtered out during `plan`, refused again during `apply`.

## 5. When something is refused

| Exit | Meaning | What to do |
|---|---|---|
| 3 | not elevated | tell the user to run in an elevated shell |
| 4 | precondition or risk gate | create a restore point first, or ask the user to accept risk explicitly |
| 5 | plan hash mismatch | regenerate the plan; do not hand-edit it |
| 6 | red line | explain why and offer a manual path |

## 6. For contributors

```powershell
.\scripts\validate-catalog.ps1     # catalog consistency
Invoke-Pester .\tests\pester        # unit tests
.\scripts\regress.ps1             # full regression (static + unit + CLI contract)
```

Adding a domain: register a probe in `catalog/probes.json`, implement it in `engine/probes/<domain>.ps1`, add an evidence entry, add a playbook, add a routing row, add tests.