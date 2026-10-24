#Requires -Version 5.1
<#
.SYNOPSIS
  报告层：把 findings / plan / journal 合成一份可交付的五段式报告。
.NOTES
  五段固定为：现状 -> 找到什么 -> 做了什么 -> 验证结果 -> 没做什么。
  缺数据时如实写「未采集」，不编造。
#>

function ConvertTo-GbText {
    param([int64]$Bytes)
    if ($Bytes -le 0) { return '0 GB' }
    return ([math]::Round($Bytes / 1GB, 2).ToString() + ' GB')
}

function Get-ReportDriveSpace {
    param($Findings)
    if (-not $Findings) { return $null }
    $p = @($Findings.probes | Where-Object { $_.id -eq 'probe.drive-space' }) | Select-Object -First 1
    if ($p -and $p.data) { return $p.data }
    return $null
}

function Format-WinMedicReport {
    param(
        [Parameter(Mandatory)]$Findings,
        $Plan = $null,
        $JournalRecords = @(),
        [string]$RunId = ''
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# WinMedic 体检与处置报告')
    [void]$sb.AppendLine('')
    $hostData = $Findings.host
    if ($hostData) {
        [void]$sb.AppendLine(('- 主机：' + $hostData.computerName + '（' + $hostData.osCaption + ' ' + $hostData.osBuild + '）'))
        [void]$sb.AppendLine(('- 采集时间：' + $Findings.generatedAt + '   探针集：' + $Findings.probeSet))
    }
    if ($RunId) { [void]$sb.AppendLine(('- 执行批次：' + $RunId)) }
    [void]$sb.AppendLine('')

    # 1 现状
    [void]$sb.AppendLine('## 1. 现状')
    $ds = Get-ReportDriveSpace -Findings $Findings
    if ($ds) {
        [void]$sb.AppendLine(('C: 共 ' + (ConvertTo-GbText -Bytes ([int64]$ds.total)) + '，可用 ' + (ConvertTo-GbText -Bytes ([int64]$ds.free)) + '，已用 ' + $ds.usedPercent + '%'))
    } else {
        [void]$sb.AppendLine('未采集磁盘现状（本次未运行 storage 探针）')
    }
    $failedProbes = @($Findings.probes | Where-Object { -not $_.ok })
    if ($failedProbes.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('未能取证的项：' + (($failedProbes | ForEach-Object { $_.id }) -join '、'))
    }
    [void]$sb.AppendLine('')

    # 2 找到什么
    [void]$sb.AppendLine('## 2. 找到什么')
    if ($Plan -and @($Plan.items).Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| 动作 | 项数 | 合计 | 级别 |')
        [void]$sb.AppendLine('|---|---:|---:|---|')
        $agg = @{}
        foreach ($it in $Plan.items) {
            $k = [string]$it.actionId
            if (-not $agg.ContainsKey($k)) { $agg[$k] = @{ size = 0L; n = 0; tier = [int]$it.tier } }
            $agg[$k].size = $agg[$k].size + [int64]$it.size
            $agg[$k].n = $agg[$k].n + 1
        }
        foreach ($k in $agg.Keys) {
            [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $k, $agg[$k].n, (ConvertTo-GbText -Bytes $agg[$k].size), $agg[$k].tier))
        }
    } else {
        [void]$sb.AppendLine('无待处置项（或尚未生成方案）')
    }
    [void]$sb.AppendLine('')

    if ($Plan -and $Plan.recommendations -and @($Plan.recommendations).Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('### 处置建议')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine((Format-RecommendationsMarkdown -Recommendations @($Plan.recommendations)))
    }

    # 3 做了什么
    [void]$sb.AppendLine('## 3. 做了什么')
    if (@($JournalRecords).Count -eq 0) {
        [void]$sb.AppendLine('本次未执行任何写操作（只读体检）')
    } else {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| 项 | 动作 | 结果 | 可用空间变化 |')
        [void]$sb.AppendLine('|---|---|---|---:|')
        foreach ($r in $JournalRecords) {
            $result = '成功'
            if ($r.result -eq 'skipped') { $result = '跳过' }
            elseif ($r.ok -eq $false) { $result = '失败' }
            $delta = 0L
            if ($null -ne $r.freeBefore -and $null -ne $r.freeAfter) { $delta = [int64]$r.freeAfter - [int64]$r.freeBefore }
            [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $r.itemId, $r.actionId, $result, (ConvertTo-GbText -Bytes $delta)))
        }
    }
    [void]$sb.AppendLine('')

    # 4 验证结果
    [void]$sb.AppendLine('## 4. 验证结果')
    $withVerify = @($JournalRecords | Where-Object { $_.verify })
    if ($withVerify.Count -eq 0) {
        [void]$sb.AppendLine('无验证记录')
    } else {
        foreach ($r in $withVerify) {
            foreach ($v in @($r.verify)) {
                [void]$sb.AppendLine(('- {0} / {1}：{2} —— {3}' -f $r.itemId, $v.rule, $(if ($v.ok) { '通过' } else { '未通过' }), $v.detail))
            }
            if ($r.pendingReboot) { [void]$sb.AppendLine(('- {0}：需重启后才完全生效' -f $r.itemId)) }
        }
    }
    $ds2 = $null
    if (@($JournalRecords).Count -gt 0) {
        $last = $JournalRecords[$JournalRecords.Count - 1]
        if ($null -ne $last.freeAfter) { $ds2 = $last.freeAfter }
    }
    if ($ds2 -ne $null) { [void]$sb.AppendLine(''); [void]$sb.AppendLine(('执行后 C: 可用：' + (ConvertTo-GbText -Bytes ([int64]$ds2)))) }
    [void]$sb.AppendLine('')

    # 5 没做什么
    [void]$sb.AppendLine('## 5. 没做什么（及原因）')
    $skip = @($JournalRecords | Where-Object { $_.result -eq 'skipped' })
    $excluded = @()
    if ($Plan -and $Plan.excluded) { $excluded = @($Plan.excluded) }
    if ($skip.Count -eq 0 -and $excluded.Count -eq 0) {
        [void]$sb.AppendLine('无排除项')
    } else {
        foreach ($s in $skip) { [void]$sb.AppendLine(('- {0} {1}：跳过（{2}）' -f $s.itemId, $s.actionId, $(if ($s.reason) { $s.reason } else { '前置检查未通过' }))) }
        $smallCount = 0
        $grouped = [ordered]@{}
        foreach ($e in $excluded) {
            $reason = [string]$e.reason
            if ($reason -match '体积过小') { $smallCount = $smallCount + 1; continue }
            if (-not $grouped.Contains($reason)) { $grouped[$reason] = @() }
            $grouped[$reason] = @($grouped[$reason]) + @([string]$e.target)
        }
        if ($smallCount -gt 0) { [void]$sb.AppendLine(('- 另有 {0} 项因体积小于 20 MB 未列入方案（明细见 plan.json 的 excluded）' -f $smallCount)) }
        foreach ($reason in $grouped.Keys) {
            foreach ($target in $grouped[$reason]) { [void]$sb.AppendLine(('- {0}：{1}' -f $target, $reason)) }
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('本报告由 WinMedic 生成；所有写操作均可在 journal 中找到并可 restore 回滚。')
    return $sb.ToString()
}