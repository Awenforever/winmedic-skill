#Requires -Version 5.1
<#
.SYNOPSIS
  U 盘/可移动盘快捷方式蠕虫检测（只读）。
.DESCRIPTION
  识别：根目录 .lnk（含指向 cmd/powershell 或含 DrvSvc/Mgrsvr 参数）、
  非打印字符隐藏目录、autorun.inf、典型载荷名。
  只输出事实与确定性判级，不自动删除。
#>

$script:UsbLegitHiddenNames = @('System Volume Information', '$RECYCLE.BIN', 'RECYCLER', '.Trashes', '.Spotlight-V100', '.fseventsd', 'found.000')

function Test-UsbShortcutPattern {
    param([string]$Target = '', [string]$Args = '')
    $reasons = @()
    if ($Target -match '(?i)\\(cmd|powershell|wscript|cscript)\.exe$') { $reasons += 'target-shell' }
    if ($Args -match '(?i)\bstart\b|DrvSvc|Mgrsvr') { $reasons += 'args-worm-pattern' }
    if ($Args -match '[^\u0020-\u007E]') { $reasons += 'args-nonprintable' }
    return @($reasons)
}

function Get-UsbSuspiciousLnk {
    param($Lnk)
    $target = ''; $args = ''; $wd = ''
    try {
        $ws = New-Object -ComObject WScript.Shell
        $s = $ws.CreateShortcut($Lnk.FullName)
        $target = [string]$s.TargetPath
        $args = [string]$s.Arguments
        $wd = [string]$s.WorkingDirectory
    } catch { }
    $reasons = @(Test-UsbShortcutPattern -Target $target -Args $args)
    if (-not $target) {
        try {
            $bytes = [IO.File]::ReadAllBytes($Lnk.FullName)
            $txt = [Text.Encoding]::Unicode.GetString($bytes) + [Text.Encoding]::ASCII.GetString($bytes)
            if ($txt -match '(?i)cmd\.exe|DrvSvc|Mgrsvr') { $reasons += 'raw-bytes-pattern' }
        } catch { }
    }
    return [pscustomobject]@{
        name = $Lnk.Name
        target = $target
        args = $args
        workingDirectory = $wd
        reasons = @($reasons)
        suspicious = ($reasons.Count -gt 0)
        sha256 = (Get-FileHash -LiteralPath $Lnk.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
    }
}

function Get-UsbDriveScan {
    param([string]$Root)
    $items = @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)
    $lnks = @($items | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.lnk' })
    $hidden = @($items | Where-Object { $_.PSIsContainer -and ($_.Attributes -band [IO.FileAttributes]::Hidden) })
    $suspHidden = @()
    $hiddenItems = 0
    foreach ($h in $hidden) {
        if ($script:UsbLegitHiddenNames -contains $h.Name) { continue }
        # 跳过重解析点/联接（火绒 BaitRoot 等勒索诱饵目录不是蠕虫工件）
        if ($h.LinkType -or $h.Target) { continue }
        $nonPrintable = ($h.Name -match '[^\u0020-\u007E]')
        $shortName = ($h.Name.Length -le 2)
        # 只把「非打印字符」或「超短名」的隐藏目录当蠕虫特征；普通 .git/.vscode 之类不算
        if (-not ($nonPrintable -or $shortName)) { continue }
        $inner = @(Get-ChildItem -LiteralPath $h.FullName -Force -ErrorAction SilentlyContinue)
        $suspHidden += [pscustomobject]@{ name = $h.Name; items = $inner.Count; nonPrintable = $nonPrintable }
        $hiddenItems += $inner.Count
    }
    $payloads = @($items | Where-Object { -not $_.PSIsContainer -and $_.Name -match '(?i)^DrvSvc|Mgrsvr|\.(scr|pif|vbs|js)$' } | ForEach-Object { $_.Name })
    $autorun = Test-Path -LiteralPath (Join-Path $Root 'autorun.inf')
    $shortcuts = @($lnks | ForEach-Object { Get-UsbSuspiciousLnk -Lnk $_ })
    $suspicious = @($shortcuts | Where-Object { $_.suspicious })
    $level = 'clean'
    if ($suspicious.Count -gt 0 -or $payloads.Count -gt 0 -or @($suspHidden | Where-Object { $_.nonPrintable }).Count -gt 0) { $level = 'infected' }
    elseif ($suspHidden.Count -gt 0 -or $autorun) { $level = 'suspicious' }
    return [pscustomobject]@{
        root = $Root
        rootCount = $items.Count
        level = $level
        lnkCount = $lnks.Count
        suspiciousShortcuts = @($suspicious)
        hiddenDirs = @($suspHidden)
        hiddenDataItems = $hiddenItems
        payloads = @($payloads)
        autorun = $autorun
        shortcuts = @($shortcuts)
    }
}

function Get-UsbWormProbe {
    param([string[]]$Roots = @())
    if (-not $Roots -or $Roots.Count -eq 0) {
        $list = @()
        foreach ($v in @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 -or $_.DriveType -eq 3 })) {
            $r = $v.DeviceID + '\'
            # 固定盘里排除系统盘（含 Windows\System32），避免把 C: 当 U 盘扫
            if ($v.DriveType -eq 3 -and (Test-Path -LiteralPath (Join-Path $r 'Windows\System32'))) { continue }
            $list += $r
        }
        $Roots = @($list)
    }
    $drives = @()
    foreach ($r in $Roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        $d = Get-UsbDriveScan -Root $r
        $vol = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $r.Substring(0,2) + "'") -ErrorAction SilentlyContinue
        $obj = [pscustomobject]@{
            letter = $r.Substring(0,2)
            fileSystem = if ($vol) { $vol.FileSystem } else { '' }
            driveType = if ($vol) { [int]$vol.DriveType } else { 0 }
            sizeGB = if ($vol) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }
            freeGB = if ($vol) { [math]::Round($vol.FreeSpace / 1GB, 1) } else { 0 }
            rootCount = $d.rootCount
            level = $d.level
            lnkCount = $d.lnkCount
            suspiciousShortcuts = @($d.suspiciousShortcuts)
            hiddenDirs = @($d.hiddenDirs)
            hiddenDataItems = $d.hiddenDataItems
            payloads = @($d.payloads)
            autorun = $d.autorun
        }
        $drives += $obj
    }
    return @{
        id = 'probe.usb-worm'; ok = $true
        data = @{
            drives = @($drives)
            counts = @{
                drives = @($drives).Count
                infected = @($drives | Where-Object { $_.level -eq 'infected' }).Count
                suspicious = @($drives | Where-Object { $_.level -eq 'suspicious' }).Count
                suspiciousShortcuts = (@($drives | ForEach-Object { @($_.suspiciousShortcuts).Count }) | Measure-Object -Sum).Sum
                hiddenDataItems = (@($drives | ForEach-Object { $_.hiddenDataItems }) | Measure-Object -Sum).Sum
            }
            note = '只读检测；处置流程见 PB-603 / 病例 0012'
        }
        candidates = @()
    }
}
