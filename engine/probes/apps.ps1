#Requires -Version 5.1
<#
.SYNOPSIS
  应用域探针（只读）。审计已安装程序、指向失效的注册表残留、疑似遗留目录。
.NOTES
  本域**刻意不提供删除动作**。原因：目录名与程序名的匹配天然有误判，
  自动删除残留的期望收益远低于误删代价。引擎只举证，处置由用户在 playbook 指导下决定。
#>

function ConvertTo-NormalizedName {
    param([string]$Text = '')
    if (-not $Text) { return '' }
    $s = $Text.ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9\u4e00-\u9fa5]+', '')
    return $s
}

function Test-NameSimilar {
    <#
      判断目录名与程序名是否可能同一个东西。
      规则：归一化后互相包含，或共同前缀 >= 5 个字符。宁漏勿错。
    #>
    param([string]$DirName, [string]$AppName)
    $d = ConvertTo-NormalizedName $DirName
    $a = ConvertTo-NormalizedName $AppName
    if ($d.Length -lt 3 -or $a.Length -lt 3) { return $false }
    if ($d.Contains($a) -or $a.Contains($d)) { return $true }

    # 词元重叠：LogiOptionsPlus 与 Logitech Options+ 靠 options 命中
    foreach ($side in @(@{ self = $d; other = $a; raw = $DirName }, @{ self = $a; other = $d; raw = $AppName })) {
        foreach ($tok in ([regex]::Split($side.raw, '[^A-Za-z0-9\u4e00-\u9fa5]+'))) {
            if ($tok.Length -lt 4) { continue }
            if ($side.other.Contains($tok.ToLowerInvariant())) { return $true }
        }
    }

    $min = [Math]::Min($d.Length, $a.Length)
    $i = 0
    while ($i -lt $min -and $d[$i] -eq $a[$i]) { $i++ }
    return ($i -ge 6)
}

function Get-ResidueSuspects {
    <#
      纯函数：给定目录名列表与已安装程序名列表，返回疑似遗留项。
      Dirs 元素：@{ name; path; size }
      Apps：字符串数组（DisplayName）
      Exclude：归一化后的白名单（精确匹配目录名）
    #>
    param(
        [array]$Dirs = @(),
        [string[]]$Apps = @(),
        [string[]]$Exclude = @(),
        [int64]$MinSizeBytes = 209715200
    )
    $suspects = @()
    $excludeSet = @{}
    foreach ($e in $Exclude) { $excludeSet[(ConvertTo-NormalizedName $e)] = $true }
    foreach ($d in $Dirs) {
        if ([int64]$d.size -lt $MinSizeBytes) { continue }
        $norm = ConvertTo-NormalizedName $d.name
        if ($excludeSet.ContainsKey($norm)) { continue }
        $matched = $false
        foreach ($a in $Apps) {
            if (Test-NameSimilar -DirName $d.name -AppName $a) { $matched = $true; break }
        }
        if (-not $matched) {
            $suspects += [pscustomobject]@{ name = $d.name; path = $d.path; size = [int64]$d.size; verdict = 'no-matching-app' }
        }
    }
    return $suspects
}

function Get-InstalledAppsProbe {
    param()
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = @()
    $orphans = @()
    foreach ($k in $keys) {
        $entries = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        foreach ($e in $entries) {
            if (-not $e.DisplayName) { continue }
            if ($e.SystemComponent -eq 1) { continue }
            $loc = [string]$e.InstallLocation
            $sizeMB = 0
            if ($e.EstimatedSize) { $sizeMB = [math]::Round([double]$e.EstimatedSize / 1024, 1) }
            $locExists = $null
            if ($loc) { $locExists = (Test-Path -LiteralPath $loc) }
            $apps += [pscustomobject]@{
                name = $e.DisplayName
                version = [string]$e.DisplayVersion
                publisher = [string]$e.Publisher
                installLocation = $loc
                estimatedSizeMB = $sizeMB
                installLocationExists = $locExists
            }
            if ($loc -and $locExists -eq $false) {
                $orphans += [pscustomobject]@{ name = $e.DisplayName; installLocation = $loc; reason = '注册表指向的目录已不存在' }
            }
        }
    }
    $dedup = @{}
    foreach ($a in $apps) { $dedup[($a.name + '|' + $a.version)] = $a }
    $unique = @($dedup.Values)
    return @{
        id = 'probe.installed-apps'
        ok = $true
        data = @{ count = $unique.Count; apps = $unique; orphanEntries = $orphans }
        candidates = @()
    }
}

function Get-AppDirsProbe {
    param(
        [int]$TimeBudgetSeconds = 90,
        [int64]$MinSizeBytes = 209715200
    )
    $roots = @(
        @{ path = $env:ProgramData;        label = 'ProgramData' },
        @{ path = (Join-Path $env:LOCALAPPDATA 'Programs'); label = 'LocalAppData\Programs' },
        @{ path = $env:LOCALAPPDATA;      label = 'LocalAppData' }
    )
    $allow = @(
        'Package Cache', 'Microsoft', 'Microsoft OneDrive', 'Temp', 'USOShared', 'USOPrivate',
        'NVIDIA', 'NVIDIA Corporation', 'AMD', 'Intel', 'Adobe', 'Steam', 'Epic',
        'Windows', 'Windows Defender', 'Windows NT', 'WindowsPowerShell', 'Packages',
        'Programs', 'ConnectedDevicesPlatform', 'D3DSCache', 'CrashDumps', 'Comms',
        'PlaceholderTileLogoFolder', 'MicrosoftEdgeUpdate', 'Google', 'Tencent', 'regid.1991-06.com.microsoft'
    )
    $dirs = @()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $truncated = $false
    foreach ($r in $roots) {
        if (-not $r.path -or -not (Test-Path -LiteralPath $r.path)) { continue }
        foreach ($d in (Get-ChildItem -LiteralPath $r.path -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($sw.Elapsed.TotalSeconds -gt $TimeBudgetSeconds) { $truncated = $true; break }
            $s = Get-PathSize -Path $d.FullName
            if ($s.Size -lt $MinSizeBytes) { continue }
            $dirs += [pscustomobject]@{ name = $d.Name; path = $d.FullName; size = [int64]$s.Size; root = $r.label }
        }
        if ($truncated) { break }
    }
    $sw.Stop()
    return @{
        id = 'probe.app-dirs'
        ok = $true
        data = @{
            scanned = $dirs.Count
            seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            truncated = $truncated
            minSizeBytes = $MinSizeBytes
            dirs = @($dirs | Sort-Object -Property { $_.size } -Descending)
            allowList = $allow
        }
        candidates = @()
    }
}

function Get-AppResidueProbe {
    param([int]$TimeBudgetSeconds = 90)
    $appsProbe = Get-InstalledAppsProbe
    $dirsProbe = Get-AppDirsProbe -TimeBudgetSeconds $TimeBudgetSeconds
    $names = @($appsProbe.data.apps | ForEach-Object { $_.name })
    $suspects = Get-ResidueSuspects -Dirs $dirsProbe.data.dirs -Apps $names -Exclude $dirsProbe.data.allowList
    $total = 0L
    foreach ($s in $suspects) { $total += [int64]$s.size }
    return @{
        id = 'probe.app-residue'
        ok = $true
        data = @{
            suspectCount = @($suspects).Count
            suspectBytes = $total
            suspects = @($suspects)
            orphanRegistryEntries = @($appsProbe.data.orphanEntries)
            dirsScanned = $dirsProbe.data.scanned
            truncated = $dirsProbe.data.truncated
            note = '本结果仅供举证，引擎不提供自动删除残留的动作；处置须由用户逐项确认。'
        }
        candidates = @()
    }
}