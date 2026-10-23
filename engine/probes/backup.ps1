#Requires -Version 5.1
<#
.SYNOPSIS
  备份能力探针（只读）：有没有备份、备份到哪、最近一次成功没有。
.NOTES
  只读判断，不触发任何备份任务。
#>

function Get-BackupVerdict {
    <#
      纯函数：综合各来源给出备份结论。
      none = 完全没有；weak = 有但不完整/不足；ok = 有可用备份。
    #>
    param([bool]$FileHistory = $false, [bool]$OneDriveKfm = $false, [bool]$SystemImage = $false, [int]$RestorePoints = 0, [int]$ShadowCopies = 0)
    $sources = @()
    if ($FileHistory) { $sources += '文件历史记录' }
    if ($OneDriveKfm) { $sources += 'OneDrive 文件夹备份' }
    if ($SystemImage) { $sources += '系统映像' }
    if ($RestorePoints -gt 0) { $sources += ('还原点 x' + $RestorePoints) }
    if ($ShadowCopies -gt 0) { $sources += ('卷影副本 x' + $ShadowCopies) }
    if ($sources.Count -eq 0) { return @{ level = 'none'; sources = @(); note = '没有任何备份机制，一次误删或故障就可能永久丢数据' } }
    if ($FileHistory -or $OneDriveKfm -or $SystemImage) {
        return @{ level = 'ok'; sources = $sources; note = '存在用户数据级备份；建议定期验证可恢复性' }
    }
    return @{ level = 'weak'; sources = $sources; note = '只有系统级恢复点/卷影副本，不能替代用户数据备份' }
}

function Get-FileHistoryState {
    $cfg = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\FileHistory\Configuration'
    $hasCfg = Test-Path -LiteralPath $cfg
    $targets = @()
    if ($hasCfg) {
        try { $targets = @(Get-ChildItem -LiteralPath $cfg -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) } catch { }
    }
    $drives = @()
    try {
        $drives = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
    } catch { }
    return @{ enabled = $hasCfg; configHosts = $targets; fixedDrives = $drives }
}

function Get-OneDriveKfmState {
    $roots = @(
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1',
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal'
    )
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        $p = Get-ItemProperty -LiteralPath $r -ErrorAction SilentlyContinue
        if ($p -and $p.UserFolder) { return @{ enabled = $true; account = $r.Split('\')[-1]; userFolder = [string]$p.UserFolder } }
    }
    return @{ enabled = $false; account = ''; userFolder = '' }
}

function Get-SystemImageState {
    $found = $false
    $detail = ''
    try {
        $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction SilentlyContinue
        if ($reg -and $reg.DisableSR -eq 1) { $detail = '系统还原已禁用' }
    } catch { }
    try {
        $wb = (& wbadmin.exe get versions 2>&1 | Out-String)
        if ($wb -match '没有找到|No backup|未找到') { $found = $false } elseif ($wb.Trim().Length -gt 20) { $found = $true }
        $detail = ($wb.Trim() -split [Environment]::NewLine)[0]
    } catch { }
    return @{ exists = $found; detail = $detail }
}

function Get-BackupStatusProbe {
    param()
    $fh = Get-FileHistoryState
    $od = Get-OneDriveKfmState
    $si = Get-SystemImageState
    $rp = @()
    try { $rp = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch { }
    $sc = @()
    try { $sc = @(Get-CimInstance Win32_ShadowCopy -ErrorAction Stop) } catch { }
    $verdict = Get-BackupVerdict -FileHistory ([bool]$fh.enabled) -OneDriveKfm ([bool]$od.enabled) -SystemImage ([bool]$si.exists) -RestorePoints @($rp).Count -ShadowCopies @($sc).Count
    return @{
        id = 'probe.backup-status'
        ok = $true
        data = @{
            level = $verdict.level
            sources = $verdict.sources
            note = $verdict.note
            fileHistory = $fh
            oneDrive = $od
            systemImage = $si
            restorePointCount = @($rp).Count
            shadowCopyCount = @($sc).Count
        }
        candidates = @()
    }
}