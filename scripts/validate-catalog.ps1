#Requires -Version 5.1
<#
.SYNOPSIS
  校验 catalog 三张表与 playbook-index 的一致性。CI 与本地提交前都要跑。
.NOTES
  退出码 0 通过，1 失败。
#>
[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$errors = New-Object System.Collections.ArrayList

function Read-JsonFile { param([string]$P) if (-not (Test-Path -LiteralPath $P)) { return $null }; return (Get-Content -LiteralPath $P -Raw -Encoding UTF8 | ConvertFrom-Json) }

$probes    = Read-JsonFile (Join-Path $Root 'catalog\probes.json')
$actions   = Read-JsonFile (Join-Path $Root 'catalog\actions.json')
$evidence  = Read-JsonFile (Join-Path $Root 'catalog\evidence.json')

foreach ($pair in @(@{ n='probes.json'; v=$probes }, @{ n='actions.json'; v=$actions }, @{ n='evidence.json'; v=$evidence })) {
    if (-not $pair.v) { [void]$errors.Add('缺少或无法解析 catalog/' + $pair.n) }
}
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host ('[X] ' + $_) }; exit 1 }

$evIds = @{}
foreach ($e in $evidence.entries) {
    if (-not $e.id) { [void]$errors.Add('evidence 条目缺少 id') ; continue }
    if ($evIds.ContainsKey($e.id)) { [void]$errors.Add('evidence id 重复: ' + $e.id) }
    $evIds[$e.id] = $true
    if (-not $e.strength) { [void]$errors.Add('evidence 缺少 strength: ' + $e.id) }
    if ($e.strength -notin @('official', 'indirect', 'empirical')) { [void]$errors.Add('evidence strength 非法: ' + $e.id) }
    if (-not $e.verifiedOn) { [void]$errors.Add('evidence 缺少 verifiedOn: ' + $e.id) }
    if ($e.strength -eq 'official' -and (-not $e.links -or $e.links.Count -eq 0)) { [void]$errors.Add('official 证据必须有链接: ' + $e.id) }
}

$actIds = @{}
foreach ($a in $actions.actions) {
    if (-not $a.id) { [void]$errors.Add('action 缺少 id'); continue }
    if ($actIds.ContainsKey($a.id)) { [void]$errors.Add('action id 重复: ' + $a.id) }
    $actIds[$a.id] = $true
    if ($a.tier -lt 1 -or $a.tier -gt 4) { [void]$errors.Add('action tier 越界: ' + $a.id) }
    if (-not $a.evidence) { [void]$errors.Add('action 缺少 evidence: ' + $a.id) }
    elseif (-not $evIds.ContainsKey($a.evidence)) { [void]$errors.Add('action 引用了不存在的 evidence: ' + $a.id + ' -> ' + $a.evidence) }
    if (-not $a.verify -or $a.verify.Count -eq 0) { [void]$errors.Add('action 缺少 verify: ' + $a.id) }
    if ($a.kind -eq 'command' -and -not $a.command) { [void]$errors.Add('command 类型缺少 command: ' + $a.id) }
    if ($a.kind -eq 'dism' -and -not $a.command) { [void]$errors.Add('dism 类型缺少 command: ' + $a.id) }
    if ($a.tier -lt 4 -and -not $a.reversible) { [void]$errors.Add('非红线动作必须标注 reversible: ' + $a.id) }
}

$probeIds = @{}
foreach ($p in $probes.probes) {
    if ($probeIds.ContainsKey($p.id)) { [void]$errors.Add('probe id 重复: ' + $p.id) }
    $probeIds[$p.id] = $true
}
foreach ($a in $actions.actions) {
    if ($a.targetsProbe -and -not $probeIds.ContainsKey($a.targetsProbe)) {
        [void]$errors.Add('action 引用了不存在的 probe: ' + $a.id + ' -> ' + $a.targetsProbe)
    }
}

# playbook-index 里的链接必须存在
$idxPath = Join-Path $Root 'playbook-index.md'
if (Test-Path -LiteralPath $idxPath) {
    $idx = Get-Content -LiteralPath $idxPath -Raw -Encoding UTF8
    $matches = [regex]::Matches($idx, '\]\((playbooks/[^)]+\.md)\)')
    foreach ($m in $matches) {
        $rel = $m.Groups[1].Value
        $full = Join-Path $Root ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full)) { [void]$errors.Add('playbook-index 链接指向不存在的文件: ' + $rel) }
    }
} else {
    [void]$errors.Add('缺少 playbook-index.md')
}

if ($errors.Count -gt 0) {
    Write-Host ('catalog 校验失败，共 ' + $errors.Count + ' 个问题:')
    $errors | ForEach-Object { Write-Host ('  [X] ' + $_) }
    exit 1
}
Write-Host ('catalog 校验通过：probes=' + $probes.probes.Count + ' actions=' + $actions.actions.Count + ' evidence=' + $evidence.entries.Count)
exit 0