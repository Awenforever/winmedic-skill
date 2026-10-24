#Requires -Version 5.1
<#
.SYNOPSIS
  病程层：把每次采集压成一条快照，只追加，形成时间序列。
.DESCRIPTION
  为什么需要它：一次快照只能说「谁最大」，说不了「为什么在涨」。
  设计约束：
    - 只追加（append-only），不改历史
    - 样本不足时 confidence=insufficient，禁止排序与速率推算（不许把猜测当结论）
    - 坏行跳过并计数，不让整条命令崩
#>

function Get-TrendProbe {
    param($Findings = $null, [string]$Id = '')
    if (-not $Findings) { return $null }
    foreach ($p in @($Findings.probes)) { if ($p -and $p.id -eq $Id) { return $p } }
    return $null
}

function Get-TrendNumber {
    <#  安全取数值：缺字段/非数字一律返回 0，绝不抛错。  #>
    param($Object = $null, [string]$Name = '')
    if (-not $Object) { return 0 }
    if (-not ($Object.PSObject.Properties.Name -contains $Name)) { return 0 }
    $v = $Object.$Name
    if ($null -eq $v) { return 0 }
    $d = 0
    if ([double]::TryParse([string]$v, [ref]$d)) { return $d }
    return 0
}

function Test-TrendMetric {
    <#  指标是否存在：同时支持 hashtable / OrderedDictionary / PSCustomObject。  #>
    param($Metrics = $null, [string]$Name = '')
    if (-not $Metrics -or -not $Name) { return $false }
    if ($Metrics -is [System.Collections.IDictionary]) { return $Metrics.Contains($Name) }
    return ($Metrics.PSObject.Properties.Name -contains $Name)
}

function Get-TrendMetricValue {
    param($Metrics = $null, [string]$Name = '')
    if (-not (Test-TrendMetric -Metrics $Metrics -Name $Name)) { return $null }
    return $Metrics[$Name]
}

function Get-TrendSnapshot {
    <#
      纯函数：从一次 findings 生成快照。
      返回 @{ ts; host; origin; volumes; metrics; workloads }
      metrics 为扁平 GB 数值，键名稳定，便于跨时间对比。
    #>
    param($Findings = $null, [string]$Origin = 'local')
    $hostName = ''
    $hp = Get-TrendProbe -Findings $Findings -Id 'probe.host'
    if ($hp -and $hp.data) { $hostName = [string]$hp.data.computerName }

    $volumes = @()
    $ds = Get-TrendProbe -Findings $Findings -Id 'probe.drive-space'
    if ($ds -and $ds.data) {
        $volumes += [pscustomobject]@{
            drive = [string]$ds.data.letter
            totalGB = [math]::Round((Get-TrendNumber -Object $ds.data -Name 'total') / 1GB, 1)
            freeGB = [math]::Round((Get-TrendNumber -Object $ds.data -Name 'free') / 1GB, 1)
            usedPercent = Get-TrendNumber -Object $ds.data -Name 'usedPercent'
        }
    }

    $m = [ordered]@{}
    if ($volumes.Count -gt 0) { $m['volume.freeGB'] = [double]$volumes[0].freeGB }

    $sf = Get-TrendProbe -Findings $Findings -Id 'probe.system-files'
    if ($sf -and $sf.data) { $m['storage.hiberfilGB'] = [math]::Round((Get-TrendNumber -Object $sf.data -Name 'hiberfilSize') / 1GB, 2) }

    $rb = Get-TrendProbe -Findings $Findings -Id 'probe.recycle-bin'
    if ($rb -and $rb.data) { $m['storage.recycleGB'] = [math]::Round((Get-TrendNumber -Object $rb.data -Name 'total') / 1GB, 2) }

    $bc = Get-TrendProbe -Findings $Findings -Id 'probe.browser-cache'
    if ($bc -and $bc.data) { $m['storage.browserCacheGB'] = [math]::Round((Get-TrendNumber -Object $bc.data -Name 'total') / 1GB, 2) }

    $oc = Get-TrendProbe -Findings $Findings -Id 'probe.office-cache'
    if ($oc -and $oc.data) { $m['storage.officeCacheGB'] = [math]::Round((Get-TrendNumber -Object $oc.data -Name 'size') / 1GB, 2) }

    $ac = Get-TrendProbe -Findings $Findings -Id 'probe.app-caches'
    if ($ac -and $ac.data) {
        $sum = 0.0
        foreach ($it in @($ac.data.items)) { $sum += (Get-TrendNumber -Object $it -Name 'size') }
        $m['storage.appCachesGB'] = [math]::Round($sum / 1GB, 2)
    }

    $wl = Get-TrendProbe -Findings $Findings -Id 'probe.workloads'
    $workloads = @()
    if ($wl -and $wl.data) {
        $m['workloads.totalCacheGB'] = [math]::Round((Get-TrendNumber -Object $wl.data -Name 'totalCacheBytes') / 1GB, 2)
        foreach ($x in @($wl.data.workloads)) {
            if (-not $x -or -not $x.installed) { continue }
            $workloads += [pscustomobject]@{ id = [string]$x.id; cacheGB = [math]::Round((Get-TrendNumber -Object $x -Name 'cacheBytes') / 1GB, 2) }
        }
    }

    $ct = Get-TrendProbe -Findings $Findings -Id 'probe.cleanup-targets'
    if ($ct -and $ct.data) {
        $ctTotal = 0.0
        foreach ($it in @($ct.data.items)) {
            $sz = Get-TrendNumber -Object $it -Name 'size'
            if ($sz -le 0) { continue }
            $ctTotal += $sz
            $key = 'cleanup.' + ([string]$it.id -replace '^clean\.', '') + '.GB'
            $m[$key] = [math]::Round($sz / 1GB, 3)
        }
        if ($ctTotal -gt 0) { $m['cleanup.totalGB'] = [math]::Round($ctTotal / 1GB, 3) }
    }

    $rr = Get-TrendProbe -Findings $Findings -Id 'probe.recovery-readiness'
    if ($rr -and $rr.data) {
        if ($rr.data.PSObject.Properties.Name -contains 'shadowStorageBytes') {
            $m['recovery.shadowGB'] = [math]::Round((Get-TrendNumber -Object $rr.data -Name 'shadowStorageBytes') / 1GB, 2)
        }
        if ($rr.data.PSObject.Properties.Name -contains 'shadowCopies') {
            $m['recovery.shadowCopies'] = @($rr.data.shadowCopies).Count
        }
        if ($rr.data.PSObject.Properties.Name -contains 'restorePoints') {
            $m['recovery.restorePoints'] = @($rr.data.restorePoints).Count
        }
    }

    return [pscustomobject]@{
        ts = (Get-IsoTimestamp)
        host = $hostName
        origin = $Origin
        probeSet = [string]$Findings.probeSet
        volumes = @($volumes)
        metrics = $m
        workloads = @($workloads)
    }
}

function Get-TrendFile {
    $d = Join-Path (Get-CdriveStateDir) 'state'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    return (Join-Path $d 'trend.jsonl')
}

function Add-TrendRecord {
    param([Parameter(Mandatory)]$Snapshot)
    $file = Get-TrendFile
    $line = ($Snapshot | ConvertTo-Json -Depth 8 -Compress)
    Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    return $file
}

function Get-TrendRecords {
    <#  返回 @{ records; badLines; path }，坏行跳过不抛错。  #>
    param([string]$Path = '')
    if (-not $Path) { $Path = Get-TrendFile }
    $records = @()
    $bad = 0
    if (-not (Test-Path -LiteralPath $Path)) { return @{ records = @(); badLines = 0; path = $Path } }
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if (-not $line.Trim()) { continue }
        try { $records += ($line | ConvertFrom-Json) } catch { $bad++ }
    }
    return @{ records = $records; badLines = $bad; path = $Path }
}

function Get-TrendGrowth {
    <#
      纯函数：一条序列的增长。
      输入：[{ ts(string); value(double) }, ...]
      返回：@{ metric; points; first; last; delta; perDay; spanDays; confidence }
      confidence: insufficient(<2 点) / low(间隔<0.5 天) / ok
    #>
    param([array]$Series = @(), [string]$Metric = '')
    $pts = @($Series | Where-Object { $null -ne $_ })
    if ($pts.Count -lt 2) {
        return @{ metric = $Metric; points = $pts.Count; first = $null; last = $null; delta = $null; perDay = $null; spanDays = 0; confidence = 'insufficient' }
    }
    $sorted = @($pts | Sort-Object { [datetime]$_.ts })
    $first = $sorted[0]
    $last = $sorted[$sorted.Count - 1]
    $t0 = [datetime]$first.ts
    $t1 = [datetime]$last.ts
    $span = ($t1 - $t0).TotalDays
    $delta = [double]$last.value - [double]$first.value
    $perDay = $null
    $conf = 'ok'
    if ($span -le 0) { $conf = 'insufficient' }
    elseif ($span -lt 0.5) { $conf = 'low'; $perDay = $null }
    else { $perDay = [math]::Round($delta / $span, 3) }
    return @{
        metric = $Metric
        points = $sorted.Count
        first = [double]$first.value
        last = [double]$last.value
        delta = [math]::Round($delta, 3)
        perDay = $perDay
        spanDays = [math]::Round($span, 2)
        confidence = $conf
    }
}

function Get-TrendMetricNames {
    param([array]$Records = @())
    $names = @()
    foreach ($r in $Records) {
        if (-not $r.metrics) { continue }
        foreach ($k in $r.metrics.PSObject.Properties.Name) { if ($names -notcontains $k) { $names += $k } }
    }
    return $names
}

function Format-TrendReport {
    param([array]$Growth = @(), [int]$Top = 10, [int]$RecordCount = 0)
    if ($RecordCount -lt 2) {
        return ('样本不足：目前只有 ' + $RecordCount + ' 条快照，至少需要 2 条才能看变化。' + [Environment]::NewLine + '先运行: winmedic.ps1 trend --record（建议配计划任务每日一次）')
    }
    $usable = @($Growth | Where-Object { $_.confidence -eq 'ok' })
    $lowConf = @($Growth | Where-Object { $_.confidence -eq 'low' })
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(('基于 ' + $RecordCount + ' 条快照'))
    if ($usable.Count -eq 0) {
        [void]$sb.AppendLine('没有足够间隔的样本，暂不给出速率（避免把短间隔误差当成趋势）。')
        return $sb.ToString().TrimEnd()
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 指标 | 首值 | 当前 | 变化 | 每天 | 跨度(天) |')
    [void]$sb.AppendLine('|---|---:|---:|---:|---:|---:|')
    $ranked = @($usable | Sort-Object -Property @{ Expression = { [math]::Abs([double]$_.delta) } } -Descending | Select-Object -First $Top)
    foreach ($g in $ranked) {
        $perDayText = if ($null -eq $g.perDay) { '-' } else { [string]$g.perDay }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $g.metric, $g.first, $g.last, $g.delta, $perDayText, $g.spanDays))
    }
    if ($lowConf.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('另有 ' + $lowConf.Count + ' 项样本间隔不足半天，已排除速率推算。'))
    }
    return $sb.ToString().TrimEnd()
}
