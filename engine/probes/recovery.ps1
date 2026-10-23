#Requires -Version 5.1
<#
.SYNOPSIS
  恢复能力探针（只读）：还原点、卷影副本、WinRE 状态。
.NOTES
  这些探针决定「出事后还能不能救」，是清理前的安全检查项。
#>

function Get-RestorePointProbe {
    param()
    $points = @()
    $errorText = ''
    try {
        $raw = Get-ComputerRestorePoint -ErrorAction Stop
        foreach ($p in $raw) {
            $points += @{ sequence = $p.SequenceNumber; description = [string]$p.Description; created = [string]$p.CreationTime }
        }
    } catch { $errorText = $_.Exception.Message }
    $protection = @{}
    try {
        $sr = Get-CimInstance -Namespace 'root\default' -ClassName SystemRestore -ErrorAction Stop | Select-Object -First 1
    } catch { }
    $vss = $null
    try { $vss = (Get-CimInstance Win32_ShadowStorage -ErrorAction Stop) } catch { }
    return @{
        id = 'probe.restore-points'
        ok = ($errorText -eq '')
        data = @{
            count = $points.Count
            points = $points
            error = $errorText
            note = '还原点数量为 0 时，任何不可逆操作前应先建还原点或外部备份'
        }
        candidates = @()
    }
}

function Get-ShadowCopyProbe {
    param()
    $copies = @()
    try {
        foreach ($c in (Get-CimInstance Win32_ShadowCopy -ErrorAction Stop)) {
            $copies += @{ id = [string]$c.ID; volume = [string]$c.VolumeName; installedDate = [string]$c.InstallDate }
        }
    } catch { }
    return @{ id = 'probe.shadow-copies'; ok = $true; data = @{ count = $copies.Count; copies = $copies }; candidates = @() }
}

function Get-WinREProbe {
    param()
    $data = @{ available = $false; enabled = $null; location = ''; raw = '' }
    try {
        $out = (& reagentc.exe /info 2>&1 | Out-String)
        $data['raw'] = $out.Trim()
        if ($out -match 'Windows 恢复环境\(WinRE\)状态\s*:\s*(\S+)|Windows Recovery Environment \(WinRE\) status\s*:\s*(\S+)') {
            $state = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
            $data['enabled'] = ($state -match '已启用|Enabled')
            $data['available'] = $true
        }
    } catch {
        $data['error'] = $_.Exception.Message
    }
    return @{ id = 'probe.winre'; ok = [bool]$data['available']; data = $data; candidates = @() }
}

function Get-RecoveryReadinessProbe {
    param()
    $rp = Get-RestorePointProbe
    $sc = Get-ShadowCopyProbe
    $re = Get-WinREProbe
    $risks = @()
    if ($rp.data.count -eq 0) { $risks += '没有系统还原点' }
    if ($sc.data.count -eq 0) { $risks += '没有卷影副本（误删后无法用「以前的版本」找回）' }
    if ($re.data.enabled -eq $false) { $risks += 'WinRE 未启用，进不去系统时无法用恢复环境' }
    $level = if ($risks.Count -eq 0) { 'ready' } elseif ($risks.Count -le 1) { 'weak' } else { 'poor' }
    return @{
        id = 'probe.recovery-readiness'
        ok = $true
        data = @{ level = $level; risks = $risks; restorePoints = $rp.data; shadowCopies = $sc.data; winre = $re.data }
        candidates = @()
    }
}