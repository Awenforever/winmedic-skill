#Requires -Version 5.1
<#
.SYNOPSIS
  方案层：把 findings 的候选转成带分级、证据、前置检查的 plan，并生成哈希。
#>

function Import-CdriveCatalog {
    param([string]$CatalogDir)
    if (-not $CatalogDir) {
        $root = $script:WinMedicRoot
        if (-not $root) {
            $libDir = $PSScriptRoot
            $root = Split-Path -Parent (Split-Path -Parent $libDir)
        }
        if (-not $root) { throw '无法定位仓库根目录，请显式传入 -CatalogDir' }
        $CatalogDir = Join-Path $root 'catalog'
    }
    $actions = @{}
    $evidence = @{}
    $aPath = Join-Path $CatalogDir 'actions.json'
    $ePath = Join-Path $CatalogDir 'evidence.json'
    if (Test-Path -LiteralPath $aPath) {
        $a = Get-Content -LiteralPath $aPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($x in $a.actions) { $actions[$x.id] = $x }
    }
    if (Test-Path -LiteralPath $ePath) {
        $e = Get-Content -LiteralPath $ePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($x in $e.entries) { $evidence[$x.id] = $x }
    }
    return @{ Actions = $actions; Evidence = $evidence }
}

function Test-PlanOriginAllowed {
    <#
      纯函数：判断计划能否在当前机器执行。
      返回 @{ allowed; offending; origin }
      - origin 为空或 local -> 允许
      - origin 等于 -AllowRemoteOrigin -> 允许（远端引擎自用）
      - 其他 -> 拒绝，offending 为首个不匹配来源
    #>
    param([Parameter(Mandatory)]$Plan, [string]$AllowRemoteOrigin = '')
    $items = @($Plan.items)
    $offending = @()
    $origins = @()
    foreach ($it in $items) {
        if (-not ($it.PSObject.Properties.Name -contains 'origin')) { continue }
        $o = [string]$it.origin
        if (-not $o) { continue }
        if ($origins -notcontains $o) { $origins += $o }
        if ($o -eq 'local') { continue }
        if ($AllowRemoteOrigin -and $o -eq $AllowRemoteOrigin) { continue }
        $offending += $o
    }
    return @{ allowed = ($offending.Count -eq 0); offending = $offending; origin = ($origins -join ',') }
}

function Get-PlanHash {
    <#
      规范化后再哈希：先显式转成字符串/int64，避免 JSON 往返后类型变化（Int64 -> Int32）
      导致同一份计划算出不同哈希。前缀 v2 用于和旧算法区分。
    #>
    param([Parameter(Mandatory)]$Items)
    $parts = @()
    foreach ($it in ($Items | Sort-Object -Property { [string]$_.id })) {
        $id = [string]$it.id
        $actionId = [string]$it.actionId
        $target = [string]$it.target
        $size = ([int64]$it.size).ToString([Globalization.CultureInfo]::InvariantCulture)
        $tier = ([int]$it.tier).ToString([Globalization.CultureInfo]::InvariantCulture)
        $parts += ($id + '|' + $actionId + '|' + $target + '|' + $size + '|' + $tier)
    }
    $basis = ($parts -join [Environment]::NewLine)
    return ('sha256:' + (Get-StringSha256 -Text ('v2' + [Environment]::NewLine + $basis)))
}

function New-CdrivePlan {
    param(
        [Parameter(Mandatory)]$Findings,
        [string]$CatalogDir
    )
    $cat = Import-CdriveCatalog -CatalogDir $CatalogDir

    $originSet = @()
    foreach ($pr in @($Findings.probes)) { if ($pr -and ($pr.PSObject.Properties.Name -contains 'origin') -and $pr.origin) { $originSet += [string]$pr.origin } }
    $planOrigin = 'local'
    if ($originSet.Count -gt 0) {
        $uniq = @($originSet | Select-Object -Unique)
        $planOrigin = if ($uniq.Count -eq 1) { $uniq[0] } else { 'mixed' }
    }
    $items = New-Object System.Collections.ArrayList
    $excluded = New-Object System.Collections.ArrayList
    $idx = 0

    $minBytes = 20MB
    $profile = Get-CdriveProfile
    $excludePatterns = @($profile.exclude)
    foreach ($cand in $Findings.candidates) {
        $act = $cat.Actions[$cand.actionId]
        if (-not $act) {
            [void]$excluded.Add(@{ target = $cand.target; reason = ('未知动作: ' + $cand.actionId) })
            continue
        }
        if ($act.tier -ge 4) {
            [void]$excluded.Add(@{ target = $cand.target; reason = 'Tier 4 红线，不进入方案' })
            continue
        }
        if (Test-ExcludedPath -Target $cand.target -Patterns $excludePatterns) {
            [void]$excluded.Add(@{ target = $cand.target; reason = (Get-ExclusionReason -Target $cand.target -Patterns $excludePatterns) })
            continue
        }
        if (Test-RedlinePath -Path $cand.target) {
            [void]$excluded.Add(@{ target = $cand.target; reason = (Get-RedlineReason -Path $cand.target) })
            continue
        }
        if ([int64]$cand.size -lt $minBytes -and -not ([int]$act.tier -eq 1 -and [int64]$cand.size -gt 50MB)) {
            [void]$excluded.Add(@{ target = $cand.target; reason = ('体积过小，不列入方案') })
            continue
        }
        $idx++
        $ev = $cat.Evidence[$act.evidence]
        $pre = Invoke-PreconditionList -Specs $act.requires
        $preObj = @()
        $blocked = $false
        foreach ($p in $pre) {
            $preObj += @{ name = $p.Name; ok = $p.Ok; detail = $p.Detail }
            if (-not $p.Ok) { $blocked = $true }
        }
        [void]$items.Add([ordered]@{
            id            = ('R' + $idx)
            origin        = $planOrigin
            actionId      = $act.id
            target        = $cand.target
            kind          = $act.kind
            size          = [int64]$cand.size
            count         = [int]$cand.count
            tier          = [int]$act.tier
            risk          = $act.risk
            reversible    = $act.reversible
            blocked       = $blocked
            preconditions = $preObj
            cautions      = @($act.cautions)
            notes         = $cand.notes
            evidence      = if ($ev) { [ordered]@{ id = $ev.id; strength = $ev.strength; links = @($ev.links); quote = $ev.quote; verifiedOn = $ev.verifiedOn } } else { $null }
        })
    }


    $recs = @()
    try { $recs = @(Get-Recommendations -Findings $Findings) } catch { $recs = @() }

    $plan = [ordered]@{
        schemaVersion = 1
        generatedAt   = (Get-IsoTimestamp)
        host          = $Findings.host
        origin        = $planOrigin
        items         = @($items)
        excluded        = @($excluded)
        excludedGroups  = @($excluded | Group-Object { [string]$_.reason } | ForEach-Object {
            [ordered]@{ reason = [string]$_.Name; count = [int]$_.Count; samples = @($_.Group | Select-Object -First 3 | ForEach-Object { [string]$_.target }) }
        })
        recommendations = @($recs)
        planHash      = (Get-PlanHash -Items $items)
    }
    return $plan
}

function Format-PlanMarkdown {
    param([Parameter(Mandatory)]$Plan)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# WinMedic 清理方案')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('- 生成时间：' + $Plan.generatedAt))
    if ($Plan.host) {
        [void]$sb.AppendLine(('- 主机：' + $Plan.host.computerName + '  系统：' + $Plan.host.osCaption + ' (' + $Plan.host.osBuild + ')'))
        [void]$sb.AppendLine(('- 管理员：' + $Plan.host.isAdmin + '  PowerShell：' + $Plan.host.psVersion))
    }
    [void]$sb.AppendLine(('- 方案哈希：' + $Plan.planHash))
    [void]$sb.AppendLine('')
    $total = 0L
    foreach ($it in $Plan.items) { $total += [int64]$it.size }
    [void]$sb.AppendLine(('**合计可释放：' + [math]::Round($total / 1GB, 2) + ' GB**'))
    [void]$sb.AppendLine('')
    $recs = @()
    if ($Plan.recommendations) { $recs = @($Plan.recommendations) }
    [void]$sb.AppendLine('## 建议（按优先级）')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine((Format-RecommendationsMarkdown -Recommendations $recs))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 汇总（按动作）')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 动作 | 项数 | 合计 | 级别 | 可回滚 |')
    [void]$sb.AppendLine('|---|---:|---:|---|---|')
    $agg = @{}
    foreach ($it in $Plan.items) {
        $k = [string]$it.actionId
        if (-not $agg.ContainsKey($k)) {
            $agg[$k] = @{ size = 0L; n = 0; tier = [int]$it.tier; rev = [string]$it.reversible }
        }
        $agg[$k].size = $agg[$k].size + [int64]$it.size
        $agg[$k].n = $agg[$k].n + 1
    }
    $ordered = @()
    foreach ($k in $agg.Keys) { $ordered += [pscustomobject]@{ key = $k; size = $agg[$k].size; n = $agg[$k].n; tier = $agg[$k].tier; rev = $agg[$k].rev } }
    $ordered = $ordered | Sort-Object -Property size -Descending
    foreach ($g in $ordered) {
        [void]$sb.AppendLine(('| {0} | {1} | {2} GB | {3} | {4} |' -f $g.key, $g.n, [math]::Round($g.size / 1GB, 2), $g.tier, $g.rev))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 明细')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| ID | 动作 | 目标 | 大小 | 级别 | 可回滚 | 前置 |')
    [void]$sb.AppendLine('|---|---|---|---:|---|---|---|')
    foreach ($it in $Plan.items) {
        $sizeGb = [math]::Round([int64]$it.size / 1GB, 2)
        $preTxt = if ($it.blocked) { '未通过' } else { '通过' }
        $target = $it.target -replace '\|', '/'
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} GB | {4} | {5} | {6} |' -f $it.id, $it.actionId, $target, $sizeGb, $it.tier, $it.reversible, $preTxt))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 证据')
    foreach ($it in $Plan.items) {
        if (-not $it.evidence) { continue }
        $e = $it.evidence
        [void]$sb.AppendLine(('- **{0}** [{1}] {2}' -f $it.id, $e.strength, $e.id))
        if ($e.quote) { [void]$sb.AppendLine(('  > ' + $e.quote)) }
        foreach ($l in $e.links) { [void]$sb.AppendLine(('  - ' + $l)) }
        [void]$sb.AppendLine(('  - 核对于 ' + $e.verifiedOn))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 已排除（为什么没进方案）')
    $exList = @($Plan.excluded)
    if ($exList.Count -eq 0) {
        [void]$sb.AppendLine('_本次没有排除项：所有候选都进入了方案，或本来就没有候选。_')
    } else {
        [void]$sb.AppendLine('| 原因 | 项数 | 示例 |')
        [void]$sb.AppendLine('|---|---:|---|')
        $groups = @($Plan.excludedGroups)
        if ($groups.Count -eq 0) {
            $groups = @($exList | Group-Object { [string]$_.reason } | ForEach-Object { [pscustomobject]@{ reason = $_.Name; count = $_.Count; samples = @($_.Group | Select-Object -First 3 | ForEach-Object { $_.target }) } })
        }
        foreach ($g in $groups) {
            $sample = (@($g.samples) -join '；')
            [void]$sb.AppendLine(('| ' + [string]$g.reason + ' | ' + [int]$g.count + ' | ' + $sample + ' |'))
        }
    }
    return $sb.ToString()
}

function Test-PlanIntegrity {
    param([Parameter(Mandatory)]$Plan)
    $recomputed = Get-PlanHash -Items $Plan.items
    return @{ Ok = ($recomputed -eq $Plan.planHash); Expected = $Plan.planHash; Actual = $recomputed }
}