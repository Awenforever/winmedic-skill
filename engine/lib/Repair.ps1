#Requires -Version 5.1
<#
.SYNOPSIS
  引擎自修复：比对当前安装与可信来源（git HEAD / dist 发布包 / 指定目录），
  还原被安全软件删除或被改坏的文件。只覆盖受管文件，不碰用户数据。
.NOTES
  写操作必须显式 -Yes；被替换的现有文件先备份到 state\repair\<时间戳>\。
#>

function Get-EngineIntegrity {
    <#  只做存在性检查：清单里的引擎文件是否还在（被安全软件删除时会缺）。  #>
    param([string]$Root)
    $manifest = Join-Path (Join-Path $Root 'engine') 'MANIFEST.txt'
    $missing = @()
    $checked = 0
    if (Test-Path -LiteralPath $manifest) {
        foreach ($rel in @(Get-Content -LiteralPath $manifest -Encoding UTF8)) {
            $rel = ([string]$rel).Trim()
            if (-not $rel) { continue }
            $checked++
            $p = Join-Path (Join-Path $Root 'engine') ($rel -replace '/', '\')
            if (-not (Test-Path -LiteralPath $p)) { $missing += ('engine/' + $rel) }
        }
    }
    return [pscustomobject]@{ ok = ($missing.Count -eq 0); checked = $checked; missing = @($missing) }
}

function Get-RepairTargets {
    param([string]$Root)
    $list = @()
    $manifest = Join-Path (Join-Path $Root 'engine') 'MANIFEST.txt'
    if (Test-Path -LiteralPath $manifest) {
        foreach ($rel in @(Get-Content -LiteralPath $manifest -Encoding UTF8)) {
            $rel = ([string]$rel).Trim()
            if (-not $rel) { continue }
            $list += ('engine/' + $rel)
        }
        $list += 'engine/MANIFEST.txt'
    }
    foreach ($sub in @('catalog', 'playbooks')) {
        $d = Join-Path $Root $sub
        if (Test-Path -LiteralPath $d) {
            foreach ($f in @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue)) { $list += ($sub + '/' + $f.Name) }
        }
    }
    foreach ($f in @('SKILL.md', 'VERSION', 'playbook-index.md')) {
        if (Test-Path -LiteralPath (Join-Path $Root $f)) { $list += $f }
    }
    return @($list | Where-Object { $_ -notmatch '\.\.' } | Sort-Object -Unique)
}

function Resolve-RepairSource {
    param([string]$Root, [string]$SourcePath = '')
    if ($SourcePath) {
        if (-not (Test-Path -LiteralPath $SourcePath)) { return @{ available = $false; reason = '指定的来源不存在: ' + $SourcePath } }
        $item = Get-Item -LiteralPath $SourcePath
        if ($item.PSIsContainer) { return @{ available = $true; kind = 'folder'; root = $item.FullName; temp = $null } }
        if ($item.Extension -ieq '.zip') {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmedic-repair-' + [guid]::NewGuid().ToString('N'))
            Expand-Archive -LiteralPath $item.FullName -DestinationPath $tmp -Force
            return @{ available = $true; kind = 'zip'; root = $tmp; temp = $tmp }
        }
        return @{ available = $false; reason = '来源既不是目录也不是 zip' }
    }
    if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
        if (Get-Command git -ErrorAction SilentlyContinue) { return @{ available = $true; kind = 'git'; root = $Root; temp = $null } }
    }
    $dist = Join-Path $Root 'dist'
    if (Test-Path -LiteralPath $dist) {
        $zip = Get-ChildItem -LiteralPath $dist -Filter 'winmedic-skill-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($zip) {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmedic-repair-' + [guid]::NewGuid().ToString('N'))
            Expand-Archive -LiteralPath $zip.FullName -DestinationPath $tmp -Force
            return @{ available = $true; kind = 'zip'; root = $tmp; temp = $tmp }
        }
    }
    foreach ($dir in @((Join-Path $env:USERPROFILE 'Downloads'), [Environment]::GetFolderPath('Desktop'))) {
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
        $zip = Get-ChildItem -LiteralPath $dir -Filter 'winmedic-skill-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($zip) {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmedic-repair-' + [guid]::NewGuid().ToString('N'))
            Expand-Archive -LiteralPath $zip.FullName -DestinationPath $tmp -Force
            return @{ available = $true; kind = 'zip-download'; root = $tmp; temp = $tmp }
        }
    }
    return @{ available = $false; reason = '找不到可信来源（git / dist 发布包 / 下载目录发布包 / --source）' }
}

function Get-RepairSourceBytes {
    param($Source, [string]$Rel)
    if ($Source.kind -eq 'git') {
        $tmp = [IO.Path]::GetTempFileName()
        try {
            $p = Start-Process -FilePath 'git' -ArgumentList @('-C', $Source.root, 'cat-file', 'blob', ('HEAD:' + $Rel)) -RedirectStandardOutput $tmp -RedirectStandardError ([IO.Path]::GetTempFileName()) -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw ('git 读取失败: ' + $Rel) }
            return [IO.File]::ReadAllBytes($tmp)
        } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    $path = Join-Path $Source.root ($Rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) { throw ('来源缺少文件: ' + $Rel) }
    return [IO.File]::ReadAllBytes($path)
}

function Get-RepairPlan {
    param([string]$Root, [string]$SourcePath = '')
    $src = Resolve-RepairSource -Root $Root -SourcePath $SourcePath
    $items = @()
    foreach ($rel in (Get-RepairTargets -Root $Root)) {
        $path = Join-Path $Root ($rel -replace '/', '\')
        $actual = $null
        if (Test-Path -LiteralPath $path) { $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
        $expected = $null
        $srcOk = $false
        if ($src.available) {
            try {
                $bytes = Get-RepairSourceBytes -Source $src -Rel $rel
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $expected = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') } finally { $sha.Dispose() }
                $srcOk = $true
            } catch { }
        }
        $status = 'ok'
        if (-not $actual) { $status = if ($srcOk) { 'missing' } else { 'unverified' } }
        elseif ($expected -and $actual -ne $expected) { $status = 'corrupt' }
        $items += [pscustomobject]@{ rel = $rel; status = $status; expected = $expected; actual = $actual }
    }
    return [pscustomobject]@{
        root = $Root; source = $src; available = $src.available; reason = $src.reason
        checked = $items.Count; items = @($items)
        todo = @($items | Where-Object { $_.status -eq 'missing' -or $_.status -eq 'corrupt' })
    }
}

function Invoke-Repair {
    param([string]$Root, [string]$SourcePath = '', [switch]$Yes)
    $plan = Get-RepairPlan -Root $Root -SourcePath $SourcePath
    if (-not $plan.available) { return [pscustomobject]@{ ok = $false; code = 4; plan = $plan; changed = @(); backupDir = '' } }
    if ($plan.todo.Count -eq 0) { return [pscustomobject]@{ ok = $true; code = 0; plan = $plan; changed = @(); backupDir = ''; dryRun = $false } }
    if (-not $Yes) { return [pscustomobject]@{ ok = $true; code = 0; plan = $plan; changed = @(); backupDir = ''; dryRun = $true } }

    $stateRoot = Get-CdriveStateDir
    $backupDir = Join-Path (Join-Path $stateRoot 'repair') (Get-Date -Format 'yyyyMMdd_HHmmss')
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $changed = @()
    $failed = @()
    foreach ($it in $plan.todo) {
        $dest = Join-Path $Root ($it.rel -replace '/', '\')
        try {
            if (Test-Path -LiteralPath $dest) {
                $b = Join-Path $backupDir ($it.rel -replace '/', '\')
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $b) | Out-Null
                Copy-Item -LiteralPath $dest -Destination $b -Force
                Set-ItemProperty -LiteralPath $dest -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            }
            $bytes = Get-RepairSourceBytes -Source $plan.source -Rel $it.rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            [IO.File]::WriteAllBytes($dest, $bytes)
            $now = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
            if ($now -ne $it.expected) { throw '写入后哈希不一致' }
            $changed += $it.rel
        } catch { $failed += ($it.rel + ': ' + $_.Exception.Message) }
    }
    return [pscustomobject]@{ ok = ($failed.Count -eq 0); code = if ($failed.Count -eq 0) { 0 } else { 7 }; plan = $plan; changed = @($changed); failed = @($failed); backupDir = $backupDir; dryRun = $false }
}
