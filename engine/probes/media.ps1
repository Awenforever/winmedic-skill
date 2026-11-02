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

function Read-BigEndian32 {
    param([byte[]]$Bytes, [int]$Offset)
    return (([uint64]$Bytes[$Offset] -shl 24) -bor ([uint64]$Bytes[$Offset + 1] -shl 16) -bor ([uint64]$Bytes[$Offset + 2] -shl 8) -bor [uint64]$Bytes[$Offset + 3])
}

function Read-BigEndian64 {
    param([byte[]]$Bytes, [int]$Offset)
    $v = [uint64]0
    for ($i = 0; $i -lt 8; $i++) { $v = ($v -shl 8) -bor [uint64]$Bytes[$Offset + $i] }
    return $v
}

function Get-Mp4CreationTimeUtc {
    <#
      纯本地解析 MP4 顶层 box，找到 moov/mvhd 的 creation_time，返回 UTC。
      不读整个文件，只按 box 大小跳转；支持 64 位 largesize 与 moov 在 mdat 之后的结构。
    #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $fs = $null
    try {
        $fs = [IO.File]::OpenRead($Path)
        $len = [uint64]$fs.Length
        $pos = [uint64]0
        $guard = 0
        while ($pos -lt $len -and $guard -lt 20000) {
            $guard++
            $fs.Position = [long]$pos
            $hdr = New-Object byte[] 8
            if ($fs.Read($hdr, 0, 8) -lt 8) { break }
            $size = Read-BigEndian32 -Bytes $hdr -Offset 0
            $type = [Text.Encoding]::ASCII.GetString($hdr, 4, 4)
            $headerSize = [uint64]8
            if ($size -eq 1) {
                $ext = New-Object byte[] 8
                if ($fs.Read($ext, 0, 8) -lt 8) { break }
                $size = Read-BigEndian64 -Bytes $ext -Offset 0
                $headerSize = [uint64]16
            } elseif ($size -eq 0) {
                $size = $len - $pos
            }
            if ($size -lt $headerSize) { break }
            if ($type -eq 'moov') {
                $payload = [uint64]($size - $headerSize)
                $take = [int][Math]::Min([uint64]4194304, $payload)
                if ($take -le 8) { return $null }
                $buf = New-Object byte[] $take
                $fs.Position = [long]($pos + $headerSize)
                $read = 0
                while ($read -lt $take) { $k = $fs.Read($buf, $read, $take - $read); if ($k -le 0) { break }; $read += $k }
                $text = [Text.Encoding]::ASCII.GetString($buf, 0, $read)
                $idx = $text.IndexOf('mvhd')
                if ($idx -lt 0) { return $null }
                $ver = $buf[$idx + 4]
                if ($ver -eq 1) {
                    $sec = Read-BigEndian64 -Bytes $buf -Offset ($idx + 12)
                } else {
                    $sec = Read-BigEndian32 -Bytes $buf -Offset ($idx + 8)
                }
                $epoch = [datetime]::SpecifyKind([datetime]'1904-01-01', 'Utc')
                $utc = $epoch.AddSeconds([double]$sec)
                return [pscustomobject]@{ ok = $true; utc = $utc; seconds = $sec; source = 'mvhd' }
            }
            $pos = $pos + $size
        }
        return $null
    } catch { return $null } finally { if ($fs) { $fs.Dispose() } }
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
        $metaSource = if ($metaText) { 'shell' } else { '' }
        if (-not $metaText) {
            $mp4 = Get-Mp4CreationTimeUtc -Path $f.FullName
            if ($mp4 -and $mp4.ok) {
                $metaText = $mp4.utc.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
                $metaSource = 'mvhd'
            }
        }
        $offset = Convert-MediaOffsetHours -FileTime $f.LastWriteTime -MetaText $metaText
        $results += [pscustomobject]@{
            path = $f.FullName
            fileModified = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            metaCreated = $metaText
            metaSource = $metaSource
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
