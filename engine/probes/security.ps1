#Requires -Version 5.1
<#
.SYNOPSIS
  安全态势探针（只读）。不修改任何安全配置。
#>

function Get-SignatureAgeDays {
    <#  纯函数：签名更新到今天的间隔天数。未知返回 -1。  #>
    param($LastUpdated, $Now = (Get-Date))
    if (-not $LastUpdated) { return -1 }
    try {
        $d = [datetime]$LastUpdated
        return [int][math]::Round(($Now - $d).TotalDays)
    } catch { return -1 }
}

function Get-SecurityVerdict {
    <#
      纯函数：根据关键开关给出总体裁决。
      入参为 $null 表示「无法读取」，不当作不安全。
    #>
    param($RealTimeEnabled, [int]$SignatureAgeDays = -1, $FirewallEnabled, $BitLockerProtected)
    $issues = @()
    if ($RealTimeEnabled -eq $false) { $issues += '实时保护已关闭' }
    if ($SignatureAgeDays -ge 0 -and $SignatureAgeDays -gt 7) { $issues += ('病毒库已 ' + $SignatureAgeDays + ' 天未更新') }
    if ($FirewallEnabled -eq $false) { $issues += '防火墙已关闭' }
    if ($BitLockerProtected -eq $false) { $issues += 'BitLocker 未保护' }
    $verdict = if ($issues.Count -eq 0) { 'ok' } elseif ($issues.Count -le 1) { 'attention' } else { 'risk' }
    return @{ verdict = $verdict; issues = $issues }
}

function Get-DefenderProbe {
    param()
    $data = @{}
    try {
        $s = Get-MpComputerStatus -ErrorAction Stop
        $data['available'] = $true
        $data['realTimeEnabled'] = [bool]$s.RealTimeProtectionEnabled
        $data['antivirusEnabled'] = [bool]$s.AntivirusEnabled
        $data['signatureVersion'] = [string]$s.AntivirusSignatureVersion
        $data['signatureLastUpdated'] = if ($s.AntivirusSignatureLastUpdated) { $s.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd') } else { '' }
        $data['signatureAgeDays'] = (Get-SignatureAgeDays -LastUpdated $s.AntivirusSignatureLastUpdated)
        $data['tamperProtection'] = [bool]$s.IsTamperProtected
    } catch {
        $data['available'] = $false
        $data['error'] = $_.Exception.Message
    }
    try {
        $p = Get-MpPreference -ErrorAction Stop
        $data['exclusionPathCount'] = @($p.ExclusionPath).Count
        $data['exclusionProcessCount'] = @($p.ExclusionProcess).Count
        $data['exclusionExtensionCount'] = @($p.ExclusionExtension).Count
    } catch { }
    return @{ id = 'probe.defender'; ok = [bool]$data['available']; data = $data; candidates = @() }
}

function Get-FirewallProbe {
    param()
    $profiles = @()
    try {
        foreach ($p in (Get-NetFirewallProfile -ErrorAction Stop)) {
            $profiles += @{ name = [string]$p.Name; enabled = [bool]$p.Enabled; inboundDefault = [string]$p.DefaultInboundAction }
        }
    } catch { }
    $allOn = ($profiles.Count -gt 0 -and @($profiles | Where-Object { -not $_.enabled }).Count -eq 0)
    return @{ id = 'probe.firewall'; ok = ($profiles.Count -gt 0); data = @{ profiles = $profiles; allEnabled = $allOn }; candidates = @() }
}

function Get-BitLockerProbe {
    param()
    $vols = @()
    try {
        foreach ($v in (Get-BitLockerVolume -ErrorAction Stop)) {
            $vols += @{
                mount = [string]$v.MountPoint
                status = [string]$v.VolumeStatus
                protection = [string]$v.ProtectionStatus
                pct = [int]$v.EncryptionPercentage
            }
        }
    } catch { }
    $systemVol = $vols | Where-Object { $_.mount -eq 'C:' } | Select-Object -First 1
    $protected = $null
    if ($systemVol) { $protected = ($systemVol.protection -eq 'On') }
    return @{ id = 'probe.bitlocker'; ok = ($vols.Count -gt 0); data = @{ volumes = $vols; systemProtected = $protected }; candidates = @() }
}

function Get-HardeningProbe {
    param()
    $data = @{}
    # SMB1
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction Stop
        $data['smb1State'] = [string]$f.State
    } catch { $data['smb1State'] = 'unknown' }
    # 安全启动
    try {
        $sb = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled -ErrorAction Stop
        $data['secureBoot'] = ([int]$sb.UEFISecureBootEnabled -eq 1)
    } catch { $data['secureBoot'] = $null }
    # 管理员组成员
    $admins = @()
    try {
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | ForEach-Object { @{ name = $_.Name; type = [string]$_.ObjectClass } })
    } catch { }
    $data['adminCount'] = $admins.Count
    $data['admins'] = $admins
    # 来宾账户
    try {
        $g = Get-LocalUser -Name 'Guest' -ErrorAction Stop
        $data['guestEnabled'] = [bool]$g.Enabled
    } catch { $data['guestEnabled'] = $null }
    return @{ id = 'probe.hardening'; ok = $true; data = $data; candidates = @() }
}

function Get-SecurityPostureProbe {
    param()
    $def = Get-DefenderProbe
    $fw = Get-FirewallProbe
    $bl = Get-BitLockerProbe
    $hd = Get-HardeningProbe
    $verdict = Get-SecurityVerdict -RealTimeEnabled $def.data['realTimeEnabled'] -SignatureAgeDays ([int]($def.data['signatureAgeDays'])) -FirewallEnabled $fw.data['allEnabled'] -BitLockerProtected $bl.data['systemProtected']
    return @{
        id = 'probe.security-posture'
        ok = $true
        data = @{
            verdict = $verdict.verdict
            issues = $verdict.issues
            defender = $def.data
            firewall = $fw.data
            bitlocker = $bl.data
            hardening = $hd.data
            note = '本探针只读；任何「加固」动作都需用户明确同意，不自动执行。'
        }
        candidates = @()
    }
}