#Requires -Version 5.1
<#
.SYNOPSIS
  cdrive 公共层：输出、编码、权限、哈希、路径、退出码。
.NOTES
  仅使用 Windows PowerShell 5.1 可用语法。禁止 emoji（GBK 兼容）。
  本文件不使用反引号转义，避免跨平台编码问题。
#>

$ErrorActionPreference = 'Stop'

# ---- 退出码 ----------------------------------------------------------------
$script:EXIT = @{
    OK           = 0
    FAIL         = 1
    USAGE        = 2
    NO_ADMIN     = 3
    PRECONDITION = 4
    PLAN_INVALID = 5
    REDLINE      = 6
    PARTIAL      = 7
    REMOTE       = 8
}

# ---- 根目录 ----------------------------------------------------------------
function Test-DirWritable {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Force -Path $Path -ErrorAction Stop | Out-Null }
        $probe = Join-Path $Path ('.wtest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

function Get-CdriveRoot {
    if ($env:CDRIVE_HOME) { return $env:CDRIVE_HOME }
    # 优先 ProgramData（多用户共享），不可写时回退到用户目录（非管理员/受控机器）
    $shared = Join-Path $env:ProgramData 'cdrive'
    if (Test-DirWritable -Path $shared) { return $shared }
    $user = Join-Path $env:LOCALAPPDATA 'winmedic'
    if (Test-DirWritable -Path $user) { return $user }
    return $shared
}

function Get-CdriveStateDir {
    $d = Get-CdriveRoot
    foreach ($sub in 'journal', 'quarantine', 'scans') {
        $p = Join-Path $d $sub
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
    }
    return $d
}

# ---- 编码 ------------------------------------------------------------------
function Set-ConsoleEncodingForCapture {
    try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936) } catch { }
}

function Set-ConsoleEncodingForOutput {
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
}

# ---- 输出 ------------------------------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK')][string]$Level = 'INFO',
        [switch]$NoNewline
    )
    $prefix = switch ($Level) { 'WARN' { '[!]' } 'ERROR' { '[X]' } 'OK' { '[OK]' } default { '[*]' } }
    $line = $prefix + ' ' + $Message
    if ($NoNewline) { Write-Host $line -NoNewline } else { Write-Host $line }
}

function Write-JsonResult {
    param([Parameter(Mandatory)]$Object, [string]$Path)
    $json = $Object | ConvertTo-Json -Depth 12
    if ($Path) {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
    } else {
        [Console]::Out.WriteLine($json)
    }
}

# ---- 权限 ------------------------------------------------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- 哈希 ------------------------------------------------------------------
function Get-StringSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $sha.Dispose() }
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

# ---- 路径 ------------------------------------------------------------------
function Resolve-CdrivePath {
    param([Parameter(Mandatory)][string]$Path)
    $p = $Path.Trim()
    if ($p.StartsWith('~')) { $p = $env:USERPROFILE + $p.Substring(1) }
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path (Get-Location).Path $p }
    return [IO.Path]::GetFullPath($p).TrimEnd('\')
}

function Test-SystemFileExists {
    <#
      对 hiberfil.sys / pagefile.sys 这类被系统独占的文件，
      Test-Path 会返回 False（实测坑 H1）。改用 dir /a:hs 解析。
    #>
    param([Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    if (-not (Test-Path -LiteralPath $parent)) { return $false }
    $cmdLine = 'dir "' + $parent + '" /a:hs /-c'
    $out = & cmd.exe /c $cmdLine 2>$null
    foreach ($line in $out) {
        if ($line -match ([regex]::Escape($leaf) + '\s*$')) { return $true }
    }
    return $false
}

function Get-PathSize {
    <#
      返回 @{ Size; Count; Basis }；Basis 为 allocated / logical / absent。
      优先使用 WizTree 索引，缺失则回退 Get-ChildItem（逻辑大小）。
    #>
    param([Parameter(Mandatory)][string]$Path, $Index = $null)
    $key = $Path.ToLower()
    if ($Index -and $Index.ContainsKey($key)) {
        $e = $Index[$key]
        return @{ Size = [int64]$e.Size; Count = [int]$e.Count; Basis = 'allocated' }
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Size = [int64]0; Count = 0; Basis = 'absent' }
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer) {
        return @{ Size = [int64]$item.Length; Count = 1; Basis = 'logical' }
    }
    $files = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
    $sum = 0L; $n = 0
    foreach ($f in $files) { $sum += $f.Length; $n++ }
    return @{ Size = $sum; Count = $n; Basis = 'logical' }
}

# ---- 时间 ------------------------------------------------------------------
function Get-IsoTimestamp { return (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK') }
function Get-CompactTimestamp { return (Get-Date).ToString('yyyyMMdd-HHmmss') }
