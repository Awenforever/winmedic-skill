#Requires -Version 5.1
<#
.SYNOPSIS
  WizTree 集成：定位可执行文件、导出 CSV、流式解析为目录索引。
.NOTES
  WizTree 缺失时上层自动降级为定向测量，本模块不抛错。
  CSV 列序：文件名称, 大小(逻辑), 分配, 修改时间, 属性, 文件, 文件夹, ...
  目录行以反斜杠结尾；第 3 行为根行。
#>

function Get-WizTreePath {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path -LiteralPath $Explicit)) { return (Resolve-Path -LiteralPath $Explicit).Path }
    if ($env:CDRIVE_WIZTREE -and (Test-Path -LiteralPath $env:CDRIVE_WIZTREE)) { return $env:CDRIVE_WIZTREE }
    $cands = @(
        'C:\Program Files\WizTree\WizTree64.exe',
        'C:\Program Files (x86)\WizTree\WizTree64.exe',
        (Join-Path $env:LOCALAPPDATA 'WizTree\WizTree64.exe'),
        (Join-Path $PSScriptRoot '..\..\vendor\WizTree64.exe')
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    $cmd = Get-Command 'WizTree64.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-WizTreeExport {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string]$Drive,
        [Parameter(Mandatory)][string]$CsvOut,
        [int]$TimeoutSeconds = 300
    )
    if (Test-Path -LiteralPath $CsvOut) { Remove-Item -LiteralPath $CsvOut -Force }
    $driveArg = $Drive.TrimEnd('\') + '\'
    $argList = @('/export=' + $CsvOut, $driveArg)
    $p = Start-Process -FilePath $ExePath -ArgumentList $argList -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not $p.HasExited) {
        if ((Get-Date) -gt $deadline) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
            throw ('WizTree 超时（' + $TimeoutSeconds + ' 秒）')
        }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 1
    if (-not (Test-Path -LiteralPath $CsvOut)) { throw 'WizTree 未生成导出文件（检查 /export 参数）' }
    return (Get-Item -LiteralPath $CsvOut)
}

function Import-WizTreeIndex {
    <#  流式解析 CSV。返回 @{ Index; Drive }。Index: 小写路径 -> @{ Size; Count }  #>
    param([Parameter(Mandatory)][string]$CsvPath)
    $index = @{}
    $drive = $null
    $reader = New-Object IO.StreamReader($CsvPath, [Text.Encoding]::UTF8)
    try {
        $lineNo = 0
        while ($null -ne ($line = $reader.ReadLine())) {
            $lineNo++
            if ($lineNo -lt 3) { continue }
            if ($line.Length -lt 4) { continue }
            if ($line[0] -ne [char]34) { continue }
            $close = $line.IndexOf([char]34, 1)
            if ($close -le 1) { continue }
            $pathValue = $line.Substring(1, $close - 1)
            $rest = $line.Substring($close + 1).TrimStart(',')
            $cols = $rest.Split(',')
            if ($cols.Count -lt 2) { continue }
            $logical = 0L; $alloc = 0L
            [void][int64]::TryParse($cols[0], [ref]$logical)
            [void][int64]::TryParse($cols[1], [ref]$alloc)
            if ($lineNo -eq 3 -and $cols.Count -ge 10) {
                $total = 0L; $free = 0L; $used = 0L
                [void][int64]::TryParse($cols[7], [ref]$total)
                [void][int64]::TryParse($cols[8], [ref]$free)
                [void][int64]::TryParse($cols[9], [ref]$used)
                $drive = @{ Total = $total; Free = $free; Used = $used }
            }
            if ($pathValue.EndsWith('\') -and $pathValue.Length -gt 3) {
                $index[$pathValue.TrimEnd('\').ToLower()] = @{ Size = $alloc; Count = -1 }
            }
        }
    } finally { $reader.Dispose() }
    return @{ Index = $index; Drive = $drive }
}

function Import-CdriveIndexCache {
    param([Parameter(Mandatory)][string]$IndexPath)
    $idx = @{}
    if (-not (Test-Path -LiteralPath $IndexPath)) { return $idx }
    $raw = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $raw.entries.PSObject.Properties) {
        $idx[$p.Name] = @{ Size = [int64]$p.Value.Size; Count = [int]$p.Value.Count }
    }
    return $idx
}