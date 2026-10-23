#Requires -Version 5.1
<#
.SYNOPSIS
  审计层：JSONL 日志的写入、读取与恢复所需信息。
#>

function New-RunId {
    return ((Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 6)))
}

function Get-JournalFile {
    param([Parameter(Mandatory)][string]$RunId)
    $dir = Join-Path (Get-CdriveStateDir) 'journal'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return (Join-Path $dir ($RunId + '.jsonl'))
}

function Write-JournalRecord {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][hashtable]$Record
    )
    $file = Get-JournalFile -RunId $RunId
    $obj = [ordered]@{ ts = (Get-IsoTimestamp); runId = $RunId }
    foreach ($k in $Record.Keys) { $obj[$k] = $Record[$k] }
    $line = ($obj | ConvertTo-Json -Depth 8 -Compress)
    Add-Content -LiteralPath $file -Value $line -Encoding UTF8
}

function Get-JournalRecords {
    param([Parameter(Mandatory)][string]$RunId)
    $file = Get-JournalFile -RunId $RunId
    $records = @()
    if (-not (Test-Path -LiteralPath $file)) { return $records }
    foreach ($line in (Get-Content -LiteralPath $file -Encoding UTF8)) {
        if (-not $line.Trim()) { continue }
        try { $records += ($line | ConvertFrom-Json) } catch { }
    }
    return $records
}

function Get-JournalList {
    $dir = Join-Path (Get-CdriveStateDir) 'journal'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return (Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -File | Sort-Object Name -Descending | ForEach-Object { $_.BaseName })
}

function Get-QuarantineRoot {
    $p = Join-Path (Get-CdriveStateDir) 'quarantine'
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
    return $p
}

function New-QuarantineDir {
    param([Parameter(Mandatory)][string]$RunId, [Parameter(Mandatory)][string]$ItemId)
    $root = Get-QuarantineRoot
    $dir = Join-Path $root (Join-Path $RunId $ItemId)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return $dir
}