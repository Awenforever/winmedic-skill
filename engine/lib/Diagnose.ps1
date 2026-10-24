#Requires -Version 5.1
<#
.SYNOPSIS
  鉴别诊断：把「要看什么」摆出来，把「结论」留给 Agent。
.DESCRIPTION
  与 v2.4 的原则一致：引擎提供事实，判断归 Agent。
  因此输出里**没有 verdict / status 字段**，只有 metric + signal + currentValue + available。
#>

function Get-DiagnosisCatalog {
    param([string]$Path = '')
    if (-not $Path) {
        $root = $script:WinMedicRoot
        if (-not $root) { $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
        $Path = Join-Path $root 'catalog\diagnoses.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($raw.diagnoses)
}

function Resolve-FindingsForDiagnosis {
    <#
      在 state/*-findings.json 里挑「对本次诊断覆盖最全」的那份，而不是盲目用最新。
      返回 @{ path; findings; coverage; total }；找不到返回 $null。
    #>
    param([string[]]$RequiredProbes = @())
    $stateDir = Join-Path (Get-CdriveStateDir) 'state'
    if (-not (Test-Path -LiteralPath $stateDir)) { return $null }
    $best = $null
    foreach ($f in @(Get-ChildItem -LiteralPath $stateDir -Filter '*-findings.json' -File -ErrorAction SilentlyContinue)) {
        try { $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        $present = @()
        foreach ($pr in @($j.probes)) { if ($pr -and $pr.id) { $present += [string]$pr.id } }
        $hit = 0
        foreach ($rp in @($RequiredProbes)) { if ($present -contains [string]$rp) { $hit++ } }
        $cand = @{ path = $f.FullName; findings = $j; coverage = $hit; total = @($RequiredProbes).Count; mtime = $f.LastWriteTime }
        if (-not $best) { $best = $cand; continue }
        if ($cand.coverage -gt $best.coverage) { $best = $cand }
        elseif ($cand.coverage -eq $best.coverage -and $cand.mtime -gt $best.mtime) { $best = $cand }
    }
    return $best
}

function Get-DiagnosisById {
    param([string]$Id = '', [string]$Path = '')
    foreach ($d in (Get-DiagnosisCatalog -Path $Path)) { if ($d.id -eq $Id) { return $d } }
    return $null
}

function Resolve-DiagnosisFacts {
    <#
      纯函数：把某个诊断所需的指标全部解析出来。
      指标来源：findings 快照（Get-TrendSnapshot）或趋势历史（days 检查项）。
    #>
    param(
        [Parameter(Mandatory)]$Diagnosis,
        [Parameter(Mandatory)]$Findings,
        [array]$TrendRecords = @()
    )
    $snap = Get-TrendSnapshot -Findings $Findings
    $present = @()
    foreach ($pr in @($Findings.probes)) { if ($pr -and $pr.id) { $present += [string]$pr.id } }
    $missing = @()
    foreach ($rp in @($Diagnosis.requiredProbes)) { if ($present -notcontains [string]$rp) { $missing += [string]$rp } }

    $facts = @()
    $hyps = @()
    foreach ($h in @($Diagnosis.hypotheses)) {
        $checks = @()
        foreach ($c in @($h.checks)) {
            $metric = [string]$c.metric
            $value = $null
            $available = $false
            $source = 'snapshot'
            $useTrend = ($c.PSObject.Properties.Name -contains 'days') -and ($c.days)
            if ($useTrend) {
                $cut = (Get-Date).AddDays(-1 * [int]$c.days)
                $series = @()
                foreach ($r in $TrendRecords) {
                    $inWindow = $true
                    try { if ([datetime]$r.ts -lt $cut) { $inWindow = $false } } catch { $inWindow = $false }
                    if (-not $inWindow) { continue }
                    if (-not $r.metrics) { continue }
                    if (-not (Test-TrendMetric -Metrics $r.metrics -Name $metric)) { continue }
                    $series += [pscustomobject]@{ ts = [string]$r.ts; value = [double](Get-TrendMetricValue -Metrics $r.metrics -Name $metric) }
                }
                $g = Get-TrendGrowth -Series $series -Metric $metric
                if ($g.confidence -eq 'ok') {
                    $available = $true; $value = $g.delta; $source = ('trend:' + [int]$c.days + 'd')
                } elseif ($g.confidence -eq 'low') {
                    $available = $true; $value = $g.delta; $source = ('trend:low(仅变化量，间隔<0.5天)')
                } else {
                    $source = ('trend:' + $g.confidence)
                }
            } else {
                if (Test-TrendMetric -Metrics $snap.metrics -Name $metric) { $available = $true; $value = (Get-TrendMetricValue -Metrics $snap.metrics -Name $metric) }
            }
            $checks += [pscustomobject]@{ metric = $metric; signal = [string]$c.signal; currentValue = $value; available = $available; source = $source }
            $facts += [pscustomobject]@{ metric = $metric; value = $value; available = $available; source = $source }
        }
        $hyps += [pscustomobject]@{
            id = [string]$h.id
            name = [string]$h.name
            why = [string]$h.why
            checks = @($checks)
            evidence = @($h.evidence)
        }
    }

    return [pscustomobject]@{
        case = [string]$Diagnosis.id
        title = [string]$Diagnosis.title
        generatedAt = (Get-IsoTimestamp)
        hypotheses = @($hyps)
        facts = @($facts)
        missingProbes = @($missing)
    }
}

function Format-DiagnosisReport {
    param([Parameter(Mandatory)]$Result)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(('# ' + $Result.case + '  ' + $Result.title))
    [void]$sb.AppendLine('')
    if (@($Result.missingProbes).Count -gt 0) {
        [void]$sb.AppendLine('缺少探针数据（结论会因此不可靠）：')
        foreach ($m in @($Result.missingProbes)) { [void]$sb.AppendLine('  - ' + $m) }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('| 假设 | 指标 | 当前值 | 判读信号 | 数据来源 |')
    [void]$sb.AppendLine('|---|---|---:|---|---|')
    foreach ($h in @($Result.hypotheses)) {
        foreach ($c in @($h.checks)) {
            $val = '-'
            if ($c.available -and $null -ne $c.currentValue) { $val = [string]$c.currentValue }
            elseif (-not $c.available) { $val = '（无数据）' }
            [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} |' -f $h.name, $c.metric, $val, $c.signal, $c.source))
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('注：本表只给事实与信号，不给结论。请逐条判断后再决定处置；数据来源含 trend 的项表示「变化量」而非绝对值，标 low 的只代表首末差、不能推算速率。')
    return $sb.ToString().TrimEnd()
}

function Format-DiagnosisList {
    param([array]$Diagnoses = @())
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| 用例 | 标题 | 假设数 | 需要的探针 |')
    [void]$sb.AppendLine('|---|---|---:|---|')
    foreach ($d in $Diagnoses) {
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $d.id, $d.title, @($d.hypotheses).Count, (@($d.requiredProbes) -join ' ')))
    }
    return $sb.ToString().TrimEnd()
}
