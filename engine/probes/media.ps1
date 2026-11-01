#Requires -Version 5.1
<#
.SYNOPSIS
  媒体时间一致性探针：比对文件系统修改时间与媒体元数据创建时间。
.DESCRIPTION
  只读。抽样常见视频扩展名，读取 Shell 的 System.Media.DateEncoded，
  偏移 >= 1 小时视为可疑（常见于相机把本地时间当 UTC 写入）。
#>

function Convert-MediaOffsetHours {
    param([datetime]$FileTime, [string]$MetaText)
    if (-not $MetaText) { return $null }
    $meta = $null
    try { $meta = [datetime]::Parse($MetaText, [Globalization.CultureInfo]::CurrentCulture) } catch { }
    if (-not $meta) { try { $meta = [datetime]::Parse($MetaText, [Globalization.CultureInfo]::InvariantCulture) } catch { } }
    if (-not $meta) { return $null }
    return [math]::Round((($meta - $FileTime).TotalHours), 1)
}

function Get-MediaTimestampProbe {
    param([int]$MaxFiles = 40, [int]$TimeBudgetSeconds = 20, [string[]]$Paths = @())
    $deadline = (Get-Date).AddSeconds($TimeBudgetSeconds)
    $roots = @()
    if ($Paths -and $Paths.Count -gt 0) {
        $roots = @($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    } else {
        $roots = @(
            [Environment]::GetFolderPath('Desktop'),
            [Environment]::GetFolderPath('MyVideos'),
            [Environment]::GetFolderPath('MyPictures'),
            [Environment]::GetFolderPath('MyDocuments')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    }
    $exts = @('.mp4', '.mov', '.mts', '.m2ts', '.avi', '.mkv')
    $files = @()
    foreach ($r in $roots) {
        foreach ($e in $exts) {
            if ((Get-Date) -gt $deadline) { break }
            $files += @(Get-ChildItem -LiteralPath $r -Recurse -Depth 3 -File -Filter ('*' + $e) -ErrorAction SilentlyContinue | Select-Object -First 30)
        }
    }
    $files = @($files | Sort-Object FullName -Unique | Select-Object -First $MaxFiles)
    $results = @()
    $shellOk = $true
    $shell = $null
    try { $shell = New-Object -ComObject Shell.Application } catch { $shellOk = $false }
    foreach ($f in $files) {
        if ((Get-Date) -gt $deadline) { break }
        $metaText = ''
        if ($shellOk -and $shell) {
            try {
                $folder = $shell.Namespace($f.DirectoryName)
                if ($folder) {
                    $item = $folder.ParseName($f.Name)
                    if ($item) { $metaText = [string]$item.ExtendedProperty('System.Media.DateEncoded') }
                }
            } catch { }
        }
        $offset = Convert-MediaOffsetHours -FileTime $f.LastWriteTime -MetaText $metaText
        $results += [pscustomobject]@{
            path = $f.FullName
            fileModified = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            metaCreated = $metaText
            offsetHours = $offset
            shifted = ($null -ne $offset -and [math]::Abs($offset) -ge 1)
        }
    }
    $withOffset = @($results | Where-Object { $null -ne $_.offsetHours })
    $maxAbs = 0
    foreach ($x in $withOffset) { $v = [math]::Abs([double]$x.offsetHours); if ($v -gt $maxAbs) { $maxAbs = $v } }
    return @{
        id = 'probe.media-timestamps'; ok = $true;
        data = @{
            sampled = $results.Count
            readable = $withOffset.Count
            shifted = @($results | Where-Object { $_.shifted }).Count
            maxAbsOffsetHours = $maxAbs
            shellAvailable = $shellOk
            files = @($results)
            note = '偏移为「元数据创建时间 - 文件系统修改时间」；>=1h 通常意味着拍摄设备时区设置错误'
        };
        candidates = @()
    }
}
