#Requires -Version 5.1
<#
.SYNOPSIS
  更新 / 驱动 / 设备域探针（只读）。
#>

function Get-DeviceErrorMeaning {
    <#  纯函数：把 ConfigManagerErrorCode 翻成人话。  #>
    param([int]$Code)
    switch ($Code) {
        0  { return '正常' }
        1  { return '设备未正确配置' }
        3  { return '驱动损坏或内存不足' }
        10 { return '设备无法启动' }
        12 { return '资源冲突' }
        18 { return '需要重新安装驱动' }
        19 { return '注册表配置损坏' }
        22 { return '设备已禁用' }
        28 { return '驱动未安装' }
        31 { return '驱动加载失败' }
        43 { return '设备报告故障，已被系统停止' }
        default { return ('未知错误码 ' + $Code) }
    }
}

function Get-PendingRebootState {
    <#  返回 @{ pending; reasons[] }  #>
    $reasons = @()
    $cbs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $wu  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $pfr = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    if (Test-Path -LiteralPath $cbs) { $reasons += 'CBS 组件安装待重启' }
    if (Test-Path -LiteralPath $wu)  { $reasons += 'Windows Update 待重启' }
    $sess = Get-ItemProperty -LiteralPath $pfr -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($sess -and $sess.PendingFileRenameOperations) { $reasons += '存在待重命名文件操作' }
    return @{ pending = ($reasons.Count -gt 0); reasons = $reasons }
}

function Get-WindowsUpdateProbe {
    param()
    $data = @{}
    $data['pendingReboot'] = (Get-PendingRebootState)
    $hot = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 5
    $data['recentHotfixes'] = @($hot | ForEach-Object { @{ id = $_.HotFixID; installedOn = if ($_.InstalledOn) { $_.InstalledOn.ToString('yyyy-MM-dd') } else { '' } } })
    $svc = @{}
    foreach ($n in 'wuauserv', 'BITS', 'TrustedInstaller', 'DoSvc') {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        $svc[$n] = if ($s) { $s.Status.ToString() } else { 'NotFound' }
    }
    $data['services'] = $svc
    $failed = @()
    try {
        $evts = Get-WinEvent -LogName 'Microsoft-Windows-WindowsUpdateClient/Operational' -MaxEvents 40 -ErrorAction Stop
        foreach ($e in $evts) {
            if ($e.Id -in @(20, 25, 31)) {
                $failed += @{ time = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm'); id = $e.Id; message = ($e.Message -split [Environment]::NewLine)[0] }
                if ($failed.Count -ge 5) { break }
            }
        }
    } catch { $data['eventLogError'] = $_.Exception.Message }
    $data['recentFailures'] = $failed
    $data['osBuild'] = [string](Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).BuildNumber
    return @{ id = 'probe.windows-update'; ok = $true; data = $data; candidates = @() }
}

function Get-DriverProbe {
    param()
    $problem = @()
    try {
        $devices = Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne $null }
        foreach ($d in $devices) {
            $problem += @{
                name = $d.Name
                deviceId = $d.DeviceID
                code = [int]$d.ConfigManagerErrorCode
                meaning = (Get-DeviceErrorMeaning -Code ([int]$d.ConfigManagerErrorCode))
            }
        }
    } catch { }
    $gpu = @()
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    if (Test-Path $base) {
        foreach ($k in (Get-ChildItem $base -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc) {
                $gpu += @{ name = $p.DriverDesc; version = [string]$p.DriverVersion; date = [string]$p.DriverDate }
            }
        }
    }
    return @{ id = 'probe.drivers'; ok = $true; data = @{ problemDevices = $problem; problemCount = $problem.Count; gpuDrivers = $gpu }; candidates = @() }
}