#Requires -Version 5.1
<#
.SYNOPSIS
  启动 / 性能域探针（全部只读）。
.NOTES
  本域当前只做诊断，不提供写动作。原因：禁用启动项、改服务启动类型属于 Tier 3，
  且 Windows 没有稳定的命令行等价物，交给用户在任务管理器里点更安全。
#>

function Get-StartupRiskCategory {
    <#
      纯函数：按名称与命令行给启动项归类，便于单测。
      返回 security | input | driver | updater | sync | vendor | unknown
    #>
    param([string]$Name = '', [string]$Command = '')
    $n = ($Name + ' ' + $Command).ToLower()
    if ($n -match 'defender|securityhealth|windows security|hips|huorong|火绒|360|kaspersky|avast|avg|bitdefender|mcafee|norton|sysdiag') { return 'security' }
    if ($n -match 'sogou|qqpinyin|输入法|ctfmon|ime') { return 'input' }
    if ($n -match 'realtek|nvidia|amd|intel|razer|logitech|logi|corsair') { return 'driver' }
    if ($n -match 'msedge_cleanup|microsoftedge|windows update|onedrivestandaloneupdater|delete cached') { return 'system' }
    if ($n -match 'update|updater|upgrade|squirrel|autoupdate') { return 'updater' }
    if ($n -match 'onedrive|baidunetdisk|dropbox|坚果云|nutstore|sync') { return 'sync' }
    if ($n -match 'vantage|lenovo|hp |dell|asus|acer|msi|game|launcher|steam|epic|adobe|ccxprocess|vmware|virtualbox|vbox') { return 'vendor' }
    return 'unknown'
}

function Get-StartupItemsProbe {
    param()
    $items = @()
    $runKeys = @(
        @{ path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';        scope = 'machine' },
        @{ path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';   scope = 'machine' },
        @{ path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';      scope = 'machine32' },
        @{ path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'; scope = 'machine32' },
        @{ path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';        scope = 'user' },
        @{ path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';   scope = 'user' }
    )
    foreach ($k in $runKeys) {
        if (-not (Test-Path -LiteralPath $k.path)) { continue }
        $props = Get-ItemProperty -LiteralPath $k.path -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $cmd = [string]$p.Value
            $items += @{
                name     = $p.Name
                command  = $cmd
                location = ('registry:' + $k.path)
                scope    = $k.scope
                category = (Get-StartupRiskCategory -Name $p.Name -Command $cmd)
            }
        }
    }
    $folders = @(
        @{ path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'); scope = 'user' },
        @{ path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); scope = 'machine' }
    )
    foreach ($f in $folders) {
        if (-not (Test-Path -LiteralPath $f.path)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $f.path -File -ErrorAction SilentlyContinue)) {
            $items += @{
                name     = $file.BaseName
                command  = $file.FullName
                location = ('startup-folder:' + $f.path)
                scope    = $f.scope
                category = (Get-StartupRiskCategory -Name $file.BaseName -Command $file.FullName)
            }
        }
    }
    $byCat = @{}
    foreach ($i in $items) {
        if (-not $byCat.ContainsKey($i.category)) { $byCat[$i.category] = 0 }
        $byCat[$i.category] = $byCat[$i.category] + 1
    }
    $suggestion = @()
    foreach ($i in $items) {
        $advice = switch ($i.category) {
            'security' { 'keep' }
            'system'   { 'keep' }
            'input'    { 'keep' }
            'driver'   { 'keep' }
            'updater'  { 'optional-disable' }
            'sync'     { 'optional-disable' }
            'vendor'   { 'optional-disable' }
            default    { 'investigate' }
        }
        $suggestion += [pscustomobject]@{ name = $i.name; category = $i.category; advice = $advice; command = $i.command; scope = $i.scope }
    }
    return @{ id = 'probe.startup-items'; ok = $true; data = @{ count = $items.Count; byCategory = $byCat; items = $suggestion }; candidates = @() }
}

function Get-BootTimeProbe {
    param()
    $data = @{ events = @(); available = $false }
    try {
        $evts = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 10 -ErrorAction Stop
        $data['available'] = $true
        $list = @()
        foreach ($e in $evts) {
            if ($e.Id -notin @(100, 101, 102, 103)) { continue }
            $ms = $null
            if ($e.Properties.Count -gt 0) { $ms = $e.Properties[0].Value }
            $list += @{ time = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'); id = $e.Id; bootMs = $ms }
        }
        $data['events'] = $list
        $boots = @($list | Where-Object { $_.id -eq 100 -and $_.bootMs })
        if ($boots.Count -gt 0) {
            $avg = ($boots | ForEach-Object { [double]$_.bootMs } | Measure-Object -Average).Average
            $data['avgBootSeconds'] = [math]::Round($avg / 1000, 1)
        }
    } catch {
        $data['error'] = $_.Exception.Message
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $data['lastBootUpTime'] = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')
        $data['uptimeHours'] = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
    } catch { }
    return @{ id = 'probe.boot-time'; ok = [bool]$data['available']; data = $data; candidates = @() }
}

function Get-PerfBaselineProbe {
    param([int]$Top = 8)
    $data = @{}
    $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
    if ($mem) {
        $data['availableMBytes'] = [int64]$mem.AvailableMBytes
        $data['committedBytes'] = [int64]$mem.CommittedBytes
        $data['commitLimit'] = [int64]$mem.CommitLimit
        if ([int64]$mem.CommitLimit -gt 0) {
            $data['commitUsedPercent'] = [math]::Round(([int64]$mem.CommittedBytes / [int64]$mem.CommitLimit) * 100, 1)
        }
    }
    $procs = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.IDProcess -ne 0 -and $_.Name -ne '_Total' -and $_.Name -ne 'Idle' }
    if ($procs) {
        $data['topCpu'] = @($procs | Sort-Object PercentProcessorTime -Descending | Select-Object -First $Top |
            ForEach-Object { @{ name = $_.Name; pid = $_.IDProcess; cpuPercent = $_.PercentProcessorTime; wsMB = [math]::Round($_.WorkingSetPrivate / 1MB, 1) } })
    }
    $disk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_Total' }
    if ($disk) {
        $data['disks'] = @($disk | ForEach-Object { @{ name = $_.Name; percentDiskTime = $_.PercentDiskTime; queue = $_.CurrentDiskQueueLength } })
    }
    $verdict = 'unknown'
    if ($data['availableMBytes'] -ne $null -and $data['availableMBytes'] -lt 1024) { $verdict = 'memory-pressure' }
    elseif ($data['commitUsedPercent'] -ne $null -and $data['commitUsedPercent'] -gt 85) { $verdict = 'commit-near-limit' }
    elseif ($data['disks']) {
        $maxQueue = 0.0
        foreach ($d in $data['disks']) { if ([double]$d['queue'] -gt $maxQueue) { $maxQueue = [double]$d['queue'] } }
        if ($maxQueue -ge 2) { $verdict = 'disk-pressure' } else { $verdict = 'ok' }
    }
    elseif ($data['availableMBytes'] -ne $null) { $verdict = 'ok' }
    $data['verdict'] = $verdict
    return @{ id = 'probe.perf-baseline'; ok = [bool]$mem; data = $data; candidates = @() }
}

function Get-DiskHealthProbe {
    param()
    $data = @{ disks = @() }
    try {
        $phys = Get-PhysicalDisk -ErrorAction Stop
        $list = @()
        foreach ($d in $phys) {
            $list += @{
                name = $d.FriendlyName
                mediaType = [string]$d.MediaType
                health = [string]$d.HealthStatus
                sizeGB = [math]::Round($d.Size / 1GB, 1)
                busType = [string]$d.BusType
            }
        }
        $data['disks'] = $list
        $boot = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($boot) { $data['systemDrive'] = 'C:' }
    } catch {
        $data['error'] = $_.Exception.Message
    }
    return @{ id = 'probe.disk-health'; ok = ($data['disks'].Count -gt 0); data = $data; candidates = @() }
}

function Get-ServicesAutoProbe {
    param()
    $svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.StartMode -eq 'Auto' }
    $running = @($svcs | Where-Object { $_.State -eq 'Running' })
    return @{ id = 'probe.services-auto'; ok = $true; data = @{ autoCount = @($svcs).Count; runningCount = $running.Count }; candidates = @() }
}