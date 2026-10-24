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

# 每个动作必须有通俗说明（不可逆确认单依赖它）
foreach ($a in $act.actions) {
    if (-not ($a.PSObject.Properties.Name -contains 'plain') -or -not $a.plain) {
        [void]$errors.Add('动作缺少 plain 通俗说明: ' + $a.id)
        continue
    }
    foreach ($f in @('what', 'why', 'consequence')) {
        if (-not $a.plain.$f) { [void]$errors.Add('动作 plain 缺少 ' + $f + ': ' + $a.id) }
    }
}

# 鉴别诊断目录
$dx = Read-JsonFile (Join-Path $Root 'catalog\diagnoses.json')
if (-not $dx) { [void]$errors.Add('缺少 catalog/diagnoses.json') }
else {
    $dxIds = @{}
    foreach ($d in $dx.diagnoses) {
        if (-not $d.id) { [void]$errors.Add('诊断缺少 id'); continue }
        if ($dxIds.ContainsKey($d.id)) { [void]$errors.Add('诊断 id 重复: ' + $d.id) }
        $dxIds[$d.id] = $true
        if (@($d.hypotheses).Count -eq 0) { [void]$errors.Add('诊断没有假设: ' + $d.id) }
        foreach ($h in @($d.hypotheses)) {
            if (-not $h.id -or -not $h.name) { [void]$errors.Add('假设缺少 id/name: ' + $d.id) }
            if (@($h.checks).Count -eq 0) { [void]$errors.Add('假设没有检查项: ' + $h.id) }
            foreach ($c in @($h.checks)) {
                if (-not $c.metric -or -not $c.signal) { [void]$errors.Add('检查项缺少 metric/signal: ' + $h.id) }
            }
        }
    }
}

# 器械台
$tl = Read-JsonFile (Join-Path $Root 'catalog\tools.json')
if (-not $tl) { [void]$errors.Add('缺少 catalog/tools.json') }
else {
    $tlIds = @{}
    foreach ($t in $tl.tools) {
        if (-not $t.id) { [void]$errors.Add('器械缺少 id'); continue }
        if ($tlIds.ContainsKey($t.id)) { [void]$errors.Add('器械 id 重复: ' + $t.id) }
        $tlIds[$t.id] = $true
        if ($t.detect.type -notin @('command', 'path', 'registry')) { [void]$errors.Add('器械 detect.type 非法: ' + $t.id) }
        if (-not $t.detect.value) { [void]$errors.Add('器械 detect.value 为空: ' + $t.id) }
        $tier = 0
        try { $tier = [int]$t.risk.tier } catch { }
        if ($tier -lt 1 -or $tier -gt 4) { [void]$errors.Add('器械 risk.tier 必须在 1-4: ' + $t.id) }
    }
}

# workloads 签名表
$wl = Read-JsonFile (Join-Path $Root 'catalog\workloads.json')
if (-not $wl) { [void]$errors.Add('缺少 catalog/workloads.json') }
else {
    $wlIds = @{}
    foreach ($w in $wl.workloads) {
        if (-not $w.id) { [void]$errors.Add('workload 缺少 id'); continue }
        if ($wlIds.ContainsKey($w.id)) { [void]$errors.Add('workload id 重复: ' + $w.id) }
        $wlIds[$w.id] = $true
        if (-not $w.name) { [void]$errors.Add('workload 缺少 name: ' + $w.id) }
        $declared = @($w.detect | Where-Object { $_.as } | ForEach-Object { [string]$_.as })
        if ($w.playbook) {
            $pb = Join-Path $Root ($w.playbook -replace '/', '\')
            if (-not (Test-Path -LiteralPath $pb)) { [void]$errors.Add('workload 引用的 playbook 不存在: ' + $w.id + ' -> ' + $w.playbook) }
        }
        foreach ($m in @($w.measure)) {
            if (-not $m.path) { [void]$errors.Add('workload measure 缺少 path: ' + $w.id); continue }
            if ($m.kind -notin @('cache', 'data', 'config', 'review')) { [void]$errors.Add('workload measure kind 非法: ' + $w.id + ' -> ' + $m.kind) }
            foreach ($mm in [regex]::Matches([string]$m.path, '\{([A-Za-z0-9_]+)\}')) {
                $key = $mm.Groups[1].Value
                if ($key -like 'kf*') { continue }
                if ($declared -notcontains $key) { [void]$errors.Add('workload 引用了未声明的占位符: ' + $w.id + ' -> {' + $key + '}') }
            }
        }
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