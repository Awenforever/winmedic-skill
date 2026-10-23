#Requires -Version 5.1
<#
.SYNOPSIS
  存储域探针（全部只读）。每个探针返回 @{ id; ok; data; candidates }。
.NOTES
  candidates 元素：@{ actionId; target; kind; size; count; notes }
  探针不得产生任何写操作。
#>

function New-Candidate {
    param([string]$ActionId, [string]$Target, [string]$Kind, [int64]$Size, [int]$Count, [string]$Notes)
    return @{ actionId = $ActionId; target = $Target; kind = $Kind; size = $Size; count = $Count; notes = $Notes }
}

function Get-HostProbe {
    param()
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $wt = Get-WizTreePath
    $data = @{
        osCaption    = if ($os) { $os.Caption } else { 'unknown' }
        osBuild      = if ($os) { $os.BuildNumber } else { '' }
        manufacturer = if ($cs) { $cs.Manufacturer } else { '' }
        model        = if ($cs) { $cs.Model } else { '' }
        psVersion    = $PSVersionTable.PSVersion.ToString()
        isAdmin      = (Test-IsAdmin)
        wiztree      = $wt
        wiztreeFound = [bool]$wt
        computerName = $env:COMPUTERNAME
        user         = $env:USERNAME
        now          = (Get-IsoTimestamp)
    }
    return @{ id = 'probe.host'; ok = $true; data = $data; candidates = @() }
}

function Get-DriveSpaceProbe {
    param([string]$Drive = 'C:')
    try {
        $d = New-Object IO.DriveInfo($Drive)
        $total = [int64]$d.TotalSize; $free = [int64]$d.AvailableFreeSpace
        $used = $total - $free
        $pct = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }
        $data = @{ letter = $Drive; total = $total; free = $free; used = $used; usedPercent = $pct }
        return @{ id = 'probe.drive-space'; ok = $true; data = $data; candidates = @() }
    } catch {
        return @{ id = 'probe.drive-space'; ok = $false; data = @{ error = $_.Exception.Message }; candidates = @() }
    }
}

function Get-SystemFilesProbe {
    param()
    $cands = @()
    $data = @{ }
    $hib = 'C:\hiberfil.sys'
    $pf  = 'C:\pagefile.sys'
    $sw  = 'C:\swapfile.sys'
    $hibExists = Test-SystemFileExists -Path $hib
    $data['hiberfilExists'] = $hibExists
    if ($hibExists) {
        $size = 0L
        try { $size = [int64](Get-Item -LiteralPath $hib -Force -ErrorAction Stop).Length } catch { }
        $data['hiberfilSize'] = $size
        if ($size -gt 0) {
            $cands += (New-Candidate -ActionId 'storage.hiberfil-off' -Target $hib -Kind 'command' -Size $size -Count 1 -Notes 'powercfg /h off')
        }
    }
    $data['pagefileExists'] = (Test-SystemFileExists -Path $pf)
    $data['swapfileExists'] = (Test-SystemFileExists -Path $sw)
    $data['hiberbootEnabled'] = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    $data['commit'] = (Get-CommitInfo)
    return @{ id = 'probe.system-files'; ok = $true; data = $data; candidates = $cands }
}

function Get-RecycleBinProbe {
    param()
    $root = 'C:\' + [char]36 + 'Recycle.Bin'
    $total = 0L; $count = 0; $perSid = @()
    if (Test-Path -LiteralPath $root) {
        foreach ($sid in (Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue)) {
            $s = Get-PathSize -Path $sid.FullName
            if ($s.Size -gt 0) {
                $perSid += @{ sid = $sid.Name; size = $s.Size }
                $total += $s.Size; $count += $s.Count
            }
        }
    }
    $cands = @()
    if ($total -gt 0) {
        $cands += (New-Candidate -ActionId 'storage.recycle-bin-empty' -Target $root -Kind 'dir' -Size $total -Count $count -Notes '移入隔离区')
    }
    return @{ id = 'probe.recycle-bin'; ok = $true; data = @{ total = $total; count = $count; perSid = $perSid }; candidates = $cands }
}

function Get-UpdateLeftoversProbe {
    param()
    $cands = @()
    $items = @(
        @{ path = 'C:\' + [char]36 + 'WinREAgent';                      action = 'storage.winreagent-remove';            kind = 'dir' },
        @{ path = 'C:\' + [char]36 + 'GetCurrent';                      action = 'storage.getcurrent-remove';            kind = 'dir' },
        @{ path = 'C:\Windows\Panther';                                action = 'storage.panther-remove';               kind = 'dir' },
        @{ path = 'C:\Windows\SoftwareDistribution\Download';          action = 'storage.software-distribution-download'; kind = 'dir' }
    )
    $measured = @()
    foreach ($it in $items) {
        if (-not (Test-Path -LiteralPath $it.path)) { continue }
        $s = Get-PathSize -Path $it.path
        if ($s.Size -le 0) { continue }
        $measured += @{ path = $it.path; size = $s.Size; count = $s.Count }
        $cands += (New-Candidate -ActionId $it.action -Target $it.path -Kind $it.kind -Size $s.Size -Count $s.Count -Notes '')
    }
    $svc = @{}
    foreach ($n in 'wuauserv', 'BITS', 'TrustedInstaller') {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        $svc[$n] = if ($s) { $s.Status.ToString() } else { 'NotFound' }
    }
    return @{ id = 'probe.update-leftovers'; ok = $true; data = @{ items = $measured; services = $svc }; candidates = $cands }
}

function Get-InstalledGpuDriverVersion {
    $out = @{}
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    if (-not (Test-Path $base)) { return $out }
    foreach ($k in (Get-ChildItem $base -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($p.DriverDesc -and $p.DriverVersion) { $out[$p.DriverDesc] = $p.DriverVersion.ToString() }
    }
    return $out
}

function Get-PackageCacheProbe {
    param([int]$MinSizeMB = 200)
    $root = 'C:\ProgramData\Package Cache'
    $cands = @()
    $items = @()
    if (-not (Test-Path -LiteralPath $root)) {
        return @{ id = 'probe.package-cache'; ok = $true; data = @{ exists = $false }; candidates = @() }
    }
    $gpu = Get-InstalledGpuDriverVersion
    foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $s = Get-PathSize -Path $dir.FullName
        if ($s.Size -lt ($MinSizeMB * 1MB)) { continue }
        $readme = Get-ChildItem -LiteralPath $dir.FullName -Filter 'installation_readme*.txt' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $kind = 'unknown'; $ver = ''
        if ($readme) {
            $head = Get-Content -LiteralPath $readme.FullName -TotalCount 12 -ErrorAction SilentlyContinue
            if ($head -match 'Intel\(R\) Graphics Driver') {
                $kind = 'intel-graphics-driver'
                $m = [regex]::Match(($head -join ' '), 'Intel\(R\) Graphics Driver:\s*([0-9\.]+)')
                if ($m.Success) { $ver = $m.Groups[1].Value }
            } elseif ($head -match 'NVIDIA|AMD|Realtek') {
                $kind = 'other-driver'
            }
        }
        $items += @{ path = $dir.FullName; size = $s.Size; kind = $kind; version = $ver }
        if ($kind -eq 'intel-graphics-driver') {
            $cands += (New-Candidate -ActionId 'storage.intel-driver-packages' -Target $dir.FullName -Kind 'dir' -Size $s.Size -Count $s.Count -Notes ('Intel 驱动包 ' + $ver))
        }
    }
    return @{ id = 'probe.package-cache'; ok = $true; data = @{ exists = $true; items = $items; gpuDrivers = $gpu }; candidates = $cands }
}

function Get-BrowserCacheProbe {
    param()
    $cands = @()
    $edgeRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
    $dirs = @()
    $total = 0L
    if (Test-Path -LiteralPath $edgeRoot) {
        $profiles = @('Default') + (Get-ChildItem -LiteralPath $edgeRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Profile *' } | ForEach-Object { $_.Name })
        foreach ($prof in $profiles) {
            foreach ($sub in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker', 'DawnGraphiteCache', 'DawnWebGPUCache', 'GrShaderCache', 'ShaderCache') {
                $p = Join-Path $edgeRoot (Join-Path $prof $sub)
                if (-not (Test-Path -LiteralPath $p)) { continue }
                $s = Get-PathSize -Path $p
                if ($s.Size -le 0) { continue }
                $dirs += @{ path = $p; size = $s.Size }
                $total += $s.Size
                $cands += (New-Candidate -ActionId 'storage.edge-cache' -Target $p -Kind 'dir' -Size $s.Size -Count $s.Count -Notes ($prof + '/' + $sub))
            }
        }
    }
    return @{ id = 'probe.browser-cache'; ok = $true; data = @{ edgeRoot = $edgeRoot; dirs = $dirs; total = $total }; candidates = $cands }
}

function Get-OfficeCacheProbe {
    param()
    $cands = @()
    $p = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\OfficeFileCache'
    $size = 0L; $count = 0
    if (Test-Path -LiteralPath $p) {
        $s = Get-PathSize -Path $p
        $size = $s.Size; $count = $s.Count
        if ($size -gt 0) {
            $cands += (New-Candidate -ActionId 'storage.office-file-cache' -Target $p -Kind 'dir' -Size $size -Count $count -Notes '')
        }
    }
    $last = $null
    if (Test-Path -LiteralPath $p) { $last = (Get-Item -LiteralPath $p).LastWriteTime }
    return @{ id = 'probe.office-cache'; ok = $true; data = @{ path = $p; size = $size; lastWrite = $last }; candidates = $cands }
}

function Get-AppCachesProbe {
    param()
    $cands = @()
    $items = @()
    $qq = Join-Path $env:APPDATA 'Tencent\QQMusic\QQMusicCache'
    if (Test-Path -LiteralPath $qq) {
        $s = Get-PathSize -Path $qq
        $items += @{ path = $qq; size = $s.Size; app = 'QQMusic' }
        if ($s.Size -gt 0) { $cands += (New-Candidate -ActionId 'storage.qqmusic-cache' -Target $qq -Kind 'dir' -Size $s.Size -Count $s.Count -Notes '') }
    }
    foreach ($sub in 'depots', 'cache') {
        $lg = Join-Path $env:ProgramData ('LogiOptionsPlus\' + $sub)
        if (Test-Path -LiteralPath $lg) {
            $s = Get-PathSize -Path $lg
            $items += @{ path = $lg; size = $s.Size; app = 'LogiOptionsPlus' }
            if ($s.Size -gt 0) { $cands += (New-Candidate -ActionId 'storage.logi-cache' -Target $lg -Kind 'dir' -Size $s.Size -Count $s.Count -Notes $sub) }
        }
    }
    return @{ id = 'probe.app-caches'; ok = $true; data = @{ items = $items }; candidates = $cands }
}

function Get-WinSxSProbe {
    param([int]$TimeoutSeconds = 600)
    $data = @{ analyzed = $false }
    $cands = @()
    $winSxS = 'C:\Windows\WinSxS'
    if (-not (Test-Path -LiteralPath $winSxS)) { return @{ id = 'probe.winsxs'; ok = $false; data = $data; candidates = @() } }
    $size = Get-PathSize -Path $winSxS
    $data['pathSize'] = $size.Size
    $data['pathBasis'] = $size.Basis
    if (Test-IsAdmin) {
        $job = Start-Job -ScriptBlock {
            $r = & dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
            return ($r | Out-String)
        }
        $done = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if ($done) {
            $text = Receive-Job -Job $job
            Remove-Job -Job $job -Force
            $data['analyzed'] = $true
            $m = [regex]::Match($text, '([0-9\.]+)\s*GB')
            $data['reclaimable'] = ([regex]::Matches($text, '([0-9\.]+)\s*GB') | ForEach-Object { $_.Groups[1].Value })
            $data['recommendsCleanup'] = ($text -match '推荐使用组件存储清理\s*:\s*是' -or $text -match 'Recommends component store cleanup\s*:\s*Yes')
            if ($data['recommendsCleanup']) {
                $cands += (New-Candidate -ActionId 'storage.winsxs-cleanup' -Target $winSxS -Kind 'dism' -Size ([int64]$size.Size) -Count 0 -Notes 'DISM 建议清理')
            }
        } else {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $data['error'] = 'DISM 分析超时（已跳过，不影响其它项）'
        }
    } else {
        $data['error'] = '需要管理员权限才能运行 DISM 分析'
    }
    return @{ id = 'probe.winsxs'; ok = $data['analyzed']; data = $data; candidates = $cands }
}

function Get-TopConsumersProbe {
    param([string]$Drive = 'C:', [int]$Top = 15)
    $driveInfo = New-Object IO.DriveInfo($Drive)
    $results = @()
    $root = $Drive.TrimEnd('\') + '\'
    foreach ($d in (Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
        $s = Get-PathSize -Path $d.FullName
        if ($s.Size -gt 0) { $results += @{ path = $d.FullName; size = $s.Size; basis = $s.Basis } }
    }
    $results = $results | Sort-Object -Property { $_.size } -Descending | Select-Object -First $Top
    return @{ id = 'probe.top-consumers'; ok = $true; data = @{ drive = $Drive; items = $results }; candidates = @() }
}