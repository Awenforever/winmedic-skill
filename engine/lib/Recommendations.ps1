#Requires -Version 5.1
<#
.SYNOPSIS
  建议层：把只读探针的结论翻译成「接下来该做什么」。
.NOTES
  与 plan.items 的区别：
    items         = 引擎可执行的动作（有 actionId，能 apply）
    recommendations = 处置建议（可能只能人工做，engineAction 为空）
  这里只做确定性规则，不做打分也不做猜测；每条建议都指向 playbook 或证据。
#>

function Get-RecProbeData {
    param($Findings, [string]$ProbeId)
    if (-not $Findings) { return $null }
    $p = @($Findings.probes | Where-Object { $_.id -eq $ProbeId }) | Select-Object -First 1
    if ($p -and $p.ok -ne $false) { return $p.data }
    return $null
}

function New-Recommendation {
    param(
        [string]$Id, [string]$Domain, [string]$Severity, [string]$Title,
        [string]$Detail = '', [string]$EngineAction = '', [string]$Playbook = '', [string]$Evidence = ''
    )
    return [ordered]@{
        id = $Id; domain = $Domain; severity = $Severity; title = $Title; detail = $Detail
        engineAction = $EngineAction; playbook = $Playbook; evidence = $Evidence
    }
}

function Get-Recommendations {
    param([Parameter(Mandatory)]$Findings)
    $recs = New-Object System.Collections.ArrayList

    # 1 待重启
    $wu = Get-RecProbeData -Findings $Findings -ProbeId 'probe.windows-update'
    if ($wu -and $wu.pendingReboot -and $wu.pendingReboot.pending) {
        $why = @($wu.pendingReboot.reasons) -join '；'
        [void]$recs.Add((New-Recommendation -Id 'rec.reboot-pending' -Domain 'updates' -Severity 'high' -Title '重启以完成挂起的安装' -Detail $why -Playbook 'playbooks/update-troubleshooting.md'))
    }

    # 2 恢复能力不足（有清理项时才提，否则是纯噪音）
    $rr = Get-RecProbeData -Findings $Findings -ProbeId 'probe.recovery-readiness'
    if ($rr -and $rr.level -ne 'ready' -and @($rr.risks).Count -gt 0) {
        [void]$recs.Add((New-Recommendation -Id 'rec.restore-point' -Domain 'recovery' -Severity 'high' -Title '先建系统还原点再动系统' -Detail ((@($rr.risks)) -join '；') -EngineAction 'recovery.create-restore-point' -Playbook 'playbooks/setup-backup.md' -Evidence 'ev.restore-point'))
    }

    # 3 备份缺失
    $bs = Get-RecProbeData -Findings $Findings -ProbeId 'probe.backup-status'
    if ($bs -and $bs.level -ne 'ok') {
        $sev = if ($bs.level -eq 'none') { 'high' } else { 'medium' }
        [void]$recs.Add((New-Recommendation -Id 'rec.backup-gap' -Domain 'backup' -Severity $sev -Title '补齐用户数据备份' -Detail $bs.note -Playbook 'playbooks/setup-backup.md'))
    }

    # 4 安全态势
    $sp = Get-RecProbeData -Findings $Findings -ProbeId 'probe.security-posture'
    if ($sp -and $sp.verdict -ne 'ok' -and @($sp.issues).Count -gt 0) {
        $sev = if ($sp.verdict -eq 'risk') { 'high' } else { 'medium' }
        [void]$recs.Add((New-Recommendation -Id 'rec.security' -Domain 'security' -Severity $sev -Title '处理安全项' -Detail ((@($sp.issues)) -join '；') -Playbook 'playbooks/endpoint-security-check.md'))
    }

    # 5 驱动/设备
    $dr = Get-RecProbeData -Findings $Findings -ProbeId 'probe.drivers'
    if ($dr -and [int]$dr.problemCount -gt 0) {
        $names = @($dr.problemDevices | Select-Object -First 3 | ForEach-Object { $_.name + '（' + $_.meaning + '）' }) -join '；'
        [void]$recs.Add((New-Recommendation -Id 'rec.device-problem' -Domain 'updates' -Severity 'medium' -Title ('处理 ' + $dr.problemCount + ' 个异常设备') -Detail $names -Playbook 'playbooks/windows-driver-device-triage.md'))
    }

    # 6 打印机
    $pr = Get-RecProbeData -Findings $Findings -ProbeId 'probe.printers'
    if ($pr -and [int]$pr.problemCount -gt 0) {
        $names = @($pr.problems | Select-Object -First 3 | ForEach-Object { $_.name + '（' + $_.verdict + '）' }) -join '；'
        [void]$recs.Add((New-Recommendation -Id 'rec.printer-problem' -Domain 'printers' -Severity 'medium' -Title ('处理 ' + $pr.problemCount + ' 台异常打印机') -Detail $names -Playbook 'playbooks/printer-repair.md'))
    }

    # 7 代理不一致
    $px = Get-RecProbeData -Findings $Findings -ProbeId 'probe.proxy-config'
    if ($px -and -not $px.summary.consistent) {
        [void]$recs.Add((New-Recommendation -Id 'rec.proxy-mismatch' -Domain 'network' -Severity 'medium' -Title '统一代理配置' -Detail $px.summary.note -Playbook 'playbooks/vpn-proxy-troubleshooting.md'))
    }

    # 8 启动项可禁用
    $su = Get-RecProbeData -Findings $Findings -ProbeId 'probe.startup-items'
    if ($su) {
        $disable = @($su.items | Where-Object { $_.advice -eq 'optional-disable' })
        if ($disable.Count -gt 0) {
            $names = @($disable | Select-Object -First 5 | ForEach-Object { $_.name }) -join '、'
            [void]$recs.Add((New-Recommendation -Id 'rec.startup-bloat' -Domain 'boot' -Severity 'low' -Title (('' + $disable.Count + ' 个启动项可考虑禁用')) -Detail $names -Playbook 'playbooks/boot-startup-bloat.md'))
        }
    }

    # 9 磁盘紧张
    $ds = Get-RecProbeData -Findings $Findings -ProbeId 'probe.drive-space'
    if ($ds -and [double]$ds.usedPercent -ge 90) {
        [void]$recs.Add((New-Recommendation -Id 'rec.disk-pressure' -Domain 'storage' -Severity 'high' -Title ('系统盘已用 ' + $ds.usedPercent + '%') -Detail ('可用 ' + [math]::Round([double]$ds.free / 1GB, 1) + ' GB') -Playbook 'playbooks/storage-disk-space-recovery.md'))
    }

    # 10 疑似残留
    $ar = Get-RecProbeData -Findings $Findings -ProbeId 'probe.app-residue'
    if ($ar -and [int]$ar.suspectCount -gt 0) {
        [void]$recs.Add((New-Recommendation -Id 'rec.app-residue' -Domain 'apps' -Severity 'low' -Title (('' + $ar.suspectCount + ' 项疑似应用残留')) -Detail ('合计 ' + [math]::Round([double]$ar.suspectBytes / 1GB, 2) + ' GB，需逐项确认，引擎不自动删除') -Playbook 'playbooks/apps-uninstall-residue.md'))
    }

    return @($recs)
}

function Format-RecommendationsMarkdown {
    param([array]$Recommendations = @())
    if ($Recommendations.Count -eq 0) { return '_无额外建议_' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| 优先级 | 域 | 建议 | 依据 | 处置 |')
    [void]$sb.AppendLine('|---|---|---|---|---|')
    $order = @{ high = 0; medium = 1; low = 2 }
    $sorted = @($Recommendations | Sort-Object -Property @{ Expression = { $order[[string]$_.severity] } })
    foreach ($r in $sorted) {
        $how = @()
        if ($r.engineAction) { $how += ('可执行: ' + $r.engineAction) }
        if ($r.playbook) { $how += ('人工: ' + $r.playbook) }
        if ($how.Count -eq 0) { $how += '人工判断' }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} |' -f $r.severity, $r.domain, $r.title, ($r.detail -replace '\|', '/'), ($how -join '<br>') ))
    }
    return $sb.ToString().TrimEnd()
}