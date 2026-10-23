#Requires -Version 5.1
<#
.SYNOPSIS
  摘要与对比：一屏体检 + 两次采集的差异。
.NOTES
  所有函数对缺失探针容错（返回「未采集」而不是报错）。
#>

function Get-ProbeData {
    param($Findings, [string]$ProbeId)
    if (-not $Findings) { return $null }
    $p = @($Findings.probes | Where-Object { $_.id -eq $ProbeId }) | Select-Object -First 1
    if ($p -and $p.ok -ne $false) { return $p.data }
    return $null
}

function Format-GbShort {
    param($Bytes)
    if ($null -eq $Bytes) { return '?' }
    return ([math]::Round([double]$Bytes / 1GB, 1).ToString() + ' GB')
}

function Get-SummaryLines {
    <#  返回 @{ domain; text; verdict } 数组  #>
    param([Parameter(Mandatory)]$Findings)
    $lines = @()

    $ds = Get-ProbeData -Findings $Findings -ProbeId 'probe.drive-space'
    if ($ds) {
        $lines += @{ domain = '磁盘'; text = ('C: 可用 ' + (Format-GbShort $ds.free) + ' / ' + (Format-GbShort $ds.total) + '（已用 ' + $ds.usedPercent + '%）'); verdict = $(if ([double]$ds.usedPercent -ge 90) { 'warn' } else { 'ok' }) }
    } else { $lines += @{ domain = '磁盘'; text = '未采集'; verdict = 'unknown' } }

    $su = Get-ProbeData -Findings $Findings -ProbeId 'probe.startup-items'
    $pb = Get-ProbeData -Findings $Findings -ProbeId 'probe.perf-baseline'
    $bootParts = @()
    if ($su) {
        $disable = 0
        foreach ($i in @($su.items)) { if ($i.advice -eq 'optional-disable') { $disable++ } }
        $bootParts += ('启动项 ' + $su.count + ' 个（可禁用 ' + $disable + '）')
    }
    if ($pb) { $bootParts += ('性能 ' + $pb.verdict) }
    if ($bootParts.Count -gt 0) {
        $bv = 'ok'
        if ($pb -and $pb.verdict -ne 'ok') { $bv = 'warn' }
        $lines += @{ domain = '启动'; text = ($bootParts -join '；'); verdict = $bv }
    } else { $lines += @{ domain = '启动'; text = '未采集'; verdict = 'unknown' } }

    $ia = Get-ProbeData -Findings $Findings -ProbeId 'probe.installed-apps'
    $ar = Get-ProbeData -Findings $Findings -ProbeId 'probe.app-residue'
    $appParts = @()
    if ($ia) { $appParts += ('已安装 ' + $ia.count + ' 个') }
    if ($ar) { $appParts += ('疑似残留 ' + $ar.suspectCount + ' 项 / ' + (Format-GbShort $ar.suspectBytes)) }
    if ($appParts.Count -gt 0) { $lines += @{ domain = '应用'; text = ($appParts -join '；'); verdict = 'info' } }
    else { $lines += @{ domain = '应用'; text = '未采集'; verdict = 'unknown' } }

    $wu = Get-ProbeData -Findings $Findings -ProbeId 'probe.windows-update'
    $dr = Get-ProbeData -Findings $Findings -ProbeId 'probe.drivers'
    $upParts = @()
    if ($wu) { $upParts += ('待重启 ' + $(if ($wu.pendingReboot.pending) { '是' } else { '否' })) }
    if ($dr) { $upParts += ('问题设备 ' + $dr.problemCount) }
    if ($upParts.Count -gt 0) {
        $uv = 'ok'
        if ($dr -and [int]$dr.problemCount -gt 0) { $uv = 'warn' }
        if ($wu -and $wu.pendingReboot.pending) { $uv = 'warn' }
        $lines += @{ domain = '更新'; text = ($upParts -join '；'); verdict = $uv }
    } else { $lines += @{ domain = '更新'; text = '未采集'; verdict = 'unknown' } }

    $na = Get-ProbeData -Findings $Findings -ProbeId 'probe.network-adapters'
    $px = Get-ProbeData -Findings $Findings -ProbeId 'probe.proxy-config'
    $netParts = @()
    if ($na) { $netParts += ('网卡 ' + @($na.adapters).Count + '（Up ' + $na.upCount + '）') }
    if ($px) { $netParts += ('代理一致 ' + $(if ($px.summary.consistent) { '是' } else { '否（' + $px.summary.note + '）' })) }
    if ($netParts.Count -gt 0) {
        $nv = 'ok'
        if ($px -and -not $px.summary.consistent) { $nv = 'warn' }
        $lines += @{ domain = '网络'; text = ($netParts -join '；'); verdict = $nv }
    } else { $lines += @{ domain = '网络'; text = '未采集'; verdict = 'unknown' } }

    $sp = Get-ProbeData -Findings $Findings -ProbeId 'probe.security-posture'
    if ($sp) {
        $sv = 'ok'
        if ($sp.verdict -eq 'attention') { $sv = 'warn' } elseif ($sp.verdict -eq 'risk') { $sv = 'bad' }
        $lines += @{ domain = '安全'; text = ('裁决 ' + $sp.verdict + $(if (@($sp.issues).Count -gt 0) { '（' + (@($sp.issues) -join '；') + '）' } else { '' })); verdict = $sv }
    } else { $lines += @{ domain = '安全'; text = '未采集'; verdict = 'unknown' } }

    $rr = Get-ProbeData -Findings $Findings -ProbeId 'probe.recovery-readiness'
    if ($rr) {
        $rv = 'ok'
        if ($rr.level -eq 'weak') { $rv = 'warn' } elseif ($rr.level -eq 'poor') { $rv = 'bad' }
        $lines += @{ domain = '恢复'; text = ('等级 ' + $rr.level + $(if (@($rr.risks).Count -gt 0) { '（' + (@($rr.risks) -join '；') + '）' } else { '' })); verdict = $rv }
    } else { $lines += @{ domain = '恢复'; text = '未采集'; verdict = 'unknown' } }

    $bs = Get-ProbeData -Findings $Findings -ProbeId 'probe.backup-status'
    if ($bs) {
        $bv2 = 'ok'
        if ($bs.level -eq 'weak') { $bv2 = 'warn' } elseif ($bs.level -eq 'none') { $bv2 = 'bad' }
        $lines += @{ domain = '备份'; text = ('等级 ' + $bs.level + $(if (@($bs.sources).Count -gt 0) { '（' + (@($bs.sources) -join '、') + '）' } else { '' })); verdict = $bv2 }
    } else { $lines += @{ domain = '备份'; text = '未采集'; verdict = 'unknown' } }

    $pr = Get-ProbeData -Findings $Findings -ProbeId 'probe.printers'
    if ($pr) {
        $pv = 'ok'
        if ([int]$pr.problemCount -gt 0) { $pv = 'warn' }
        $lines += @{ domain = '外设'; text = ('打印机 ' + $pr.count + '；问题 ' + $pr.problemCount); verdict = $pv }
    } else { $lines += @{ domain = '外设'; text = '未采集'; verdict = 'unknown' } }

    return $lines
}

function Format-WinMedicSummary {
    param([Parameter(Mandatory)]$Findings)
    $sb = New-Object System.Text.StringBuilder
    $h = $Findings.host
    [void]$sb.AppendLine('WinMedic 体检摘要')
    if ($h) { [void]$sb.AppendLine(('  主机: ' + $h.computerName + ' / ' + $h.osCaption + ' ' + $h.osBuild + ' / 探针集 ' + $Findings.probeSet)) }
    [void]$sb.AppendLine(('  采集: ' + $Findings.generatedAt))
    [void]$sb.AppendLine('')
    $mark = @{ ok = '[OK]  '; warn = '[WARN]'; bad = '[BAD] '; info = '[--]  '; unknown = '[?]   ' }
    foreach ($l in (Get-SummaryLines -Findings $Findings)) {
        [void]$sb.AppendLine(($mark[$l.verdict] + ' ' + $l.domain + '  ' + $l.text))
    }
    return $sb.ToString().TrimEnd()
}

function Get-DiffMetrics {
    <#  抽取可对比的指标（缺失的跳过）  #>
    param($Findings)
    $m = [ordered]@{}
    $ds = Get-ProbeData -Findings $Findings -ProbeId 'probe.drive-space'
    if ($ds) { $m['可用空间GB'] = [math]::Round([double]$ds.free / 1GB, 2) }
    $su = Get-ProbeData -Findings $Findings -ProbeId 'probe.startup-items'
    if ($su) { $m['启动项数'] = [int]$su.count }
    $wu = Get-ProbeData -Findings $Findings -ProbeId 'probe.windows-update'
    if ($wu) { $m['待重启'] = $(if ($wu.pendingReboot.pending) { 1 } else { 0 }) }
    $dr = Get-ProbeData -Findings $Findings -ProbeId 'probe.drivers'
    if ($dr) { $m['问题设备'] = [int]$dr.problemCount }
    $pr = Get-ProbeData -Findings $Findings -ProbeId 'probe.printers'
    if ($pr) { $m['打印机问题'] = [int]$pr.problemCount }
    $ar = Get-ProbeData -Findings $Findings -ProbeId 'probe.app-residue'
    if ($ar) { $m['疑似残留GB'] = [math]::Round([double]$ar.suspectBytes / 1GB, 2) }
    $sp = Get-ProbeData -Findings $Findings -ProbeId 'probe.security-posture'
    if ($sp) { $m['安全裁决'] = [string]$sp.verdict }
    $rr = Get-ProbeData -Findings $Findings -ProbeId 'probe.recovery-readiness'
    if ($rr) { $m['恢复等级'] = [string]$rr.level }
    $bs = Get-ProbeData -Findings $Findings -ProbeId 'probe.backup-status'
    if ($bs) { $m['备份等级'] = [string]$bs.level }
    return $m
}

function Format-FindingsDiff {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    $b = Get-DiffMetrics -Findings $Before
    $a = Get-DiffMetrics -Findings $After
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('WinMedic 采集对比')
    [void]$sb.AppendLine(('  基线: ' + $Before.generatedAt + '（' + $Before.probeSet + '）'))
    [void]$sb.AppendLine(('  对比: ' + $After.generatedAt + '（' + $After.probeSet + '）'))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 指标 | 基线 | 对比 | 变化 |')
    [void]$sb.AppendLine('|---|---:|---:|---:|')
    $keys = @($b.Keys) + @($a.Keys) | Select-Object -Unique
    foreach ($k in $keys) {
        $bv = if ($b.Contains($k)) { $b[$k] } else { '-' }
        $av = if ($a.Contains($k)) { $a[$k] } else { '-' }
        $delta = ''
        if ($b.Contains($k) -and $a.Contains($k) -and ($bv -is [int] -or $bv -is [double])) {
            $d = [double]$av - [double]$bv
            if ($d -ne 0) { $delta = $(if ($d -gt 0) { '+' } else { '' }) + [math]::Round($d, 2) }
        } elseif ($b.Contains($k) -and $a.Contains($k) -and $bv -ne $av) {
            $delta = '变化'
        }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $k, $bv, $av, $delta))
    }
    return $sb.ToString().TrimEnd()
}