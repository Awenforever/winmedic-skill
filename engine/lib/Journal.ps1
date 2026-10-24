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
function Restore-JournalQuarantine {
    <#
      把一条隔离记录移回原位置。可单测，不依赖管理员权限。
      返回 @{ ok; detail; target }
    #>
    param([Parameter(Mandatory)]$Record)
    $q = [string]$Record.quarantinePath
    $dest = [string]$Record.target
    if (-not $q -or -not $dest) { return @{ ok = $false; detail = '记录缺少 quarantinePath 或 target'; target = $dest } }
    if (-not (Test-Path -LiteralPath $q)) { return @{ ok = $false; detail = '隔离区文件已不存在'; target = $dest } }
    if (Test-Path -LiteralPath $dest) { return @{ ok = $false; detail = '原位置已存在同名目标，拒绝覆盖'; target = $dest } }
    $parent = Split-Path -Parent $dest
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        try { New-Item -ItemType Directory -Force -Path $parent | Out-Null } catch { }
    }
    try {
        Move-Item -LiteralPath $q -Destination $dest -Force -ErrorAction Stop
        return @{ ok = $true; detail = '已恢复'; target = $dest }
    } catch {
        return @{ ok = $false; detail = $_.Exception.Message; target = $dest }
    }
}

function Get-QuarantineDirFor {
    param([string]$RunId, [string]$ItemId)
    return (Join-Path (Join-Path (Get-QuarantineRoot) $RunId) $ItemId)
}

function Get-JournalOrphans {
    <#
      预写日志里「有 begin、没有 done」的条目 = 上次执行中途中断。
      若隔离区里确有内容，说明文件已被移走但没记账 —— 这是可以救回来的。
      返回 @{ itemId; actionId; target; quarantinePath; hasQuarantine }
    #>
    param([Parameter(Mandatory)][string]$RunId)
    $records = Get-JournalRecords -RunId $RunId
    $begun = [ordered]@{}
    $done = @{}
    foreach ($r in $records) {
        $phase = ''
        if ($r.PSObject.Properties.Name -contains 'phase') { $phase = [string]$r.phase }
        if ($phase -eq 'begin') { if (-not $begun.Contains([string]$r.itemId)) { $begun[[string]$r.itemId] = $r } }
        elseif ($phase -eq 'done') { $done[[string]$r.itemId] = $true }
    }
    $orphans = @()
    foreach ($id in $begun.Keys) {
        if ($done.ContainsKey($id)) { continue }
        $r = $begun[$id]
        $qdir = Get-QuarantineDirFor -RunId $RunId -ItemId $id
        $has = $false
        if (Test-Path -LiteralPath $qdir) {
            if (@(Get-ChildItem -LiteralPath $qdir -Force -ErrorAction SilentlyContinue).Count -gt 0) { $has = $true }
        }
        $orphans += [pscustomobject]@{ itemId = $id; actionId = [string]$r.actionId; target = [string]$r.target; quarantinePath = $qdir; hasQuarantine = $has }
    }
    return $orphans
}
