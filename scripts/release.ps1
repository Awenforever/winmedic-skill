#Requires -Version 5.1
<#
.SYNOPSIS
  生成可分发的发布包（zip + SHA256），不需要仓库其它文件。
.NOTES
  dist/winmedic-skill-<ver>.zip 内含 engine/catalog/playbooks/cases/docs/SKILL.md/README*/LICENSE/VERSION。
#>
[CmdletBinding()]
param([string]$OutDir = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ver = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$name = 'winmedic-skill-' + $ver
$zip = Join-Path $OutDir ($name + '.zip')
if (Test-Path $zip) { Remove-Item $zip -Force }
$items = @()
foreach ($i in @('engine', 'catalog', 'playbooks', 'cases', 'docs', 'SKILL.md', 'README.md', 'README.en.md', 'LICENSE', 'VERSION', 'CHANGELOG.md', 'SECURITY.md', 'CONTRIBUTING.md', 'playbook-index.md')) {
    $p = Join-Path $root $i
    if (Test-Path $p) { $items += $p }
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fs = [IO.File]::Open($zip, [IO.FileMode]::Create)
$arch = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
foreach ($item in $items) {
    if (Test-Path -LiteralPath $item -PathType Leaf) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arch, $item, (Split-Path -Leaf $item))
    } else {
        $base = Split-Path -Leaf $item
        Get-ChildItem -LiteralPath $item -Recurse -File | ForEach-Object {
            $relPath = $_.FullName.Substring($item.Length).TrimStart('\')
            $entry = $base + '/' + ($relPath -replace '\\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arch, $_.FullName, $entry)
        }
    }
}
$arch.Dispose()
$fs.Dispose()
# 自校验：zip 内每个条目必须与源文件内容一致，且数量吻合
$bad = @()
$z = [IO.Compression.ZipFile]::OpenRead($zip)
foreach ($e in $z.Entries) {
    if ($e.FullName.EndsWith('/')) { continue }
    $src = Join-Path $root ($e.FullName -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src)) { $bad += ('多余条目: ' + $e.FullName); continue }
    $stream = $e.Open()
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        $inZip = (-join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }))
        $sha.Dispose()
    } finally { $stream.Dispose() }
    $onDisk = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLower()
    if ($inZip -ne $onDisk) { $bad += ('内容不一致: ' + $e.FullName) }
}
$z.Dispose()
if ($bad.Count -gt 0) { Write-Host ('自校验失败 ' + $bad.Count + ' 项:') -ForegroundColor Red; $bad | ForEach-Object { Write-Host ('  [X] ' + $_) }; exit 1 }
Write-Host '自校验: 条目与源文件内容一致'

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
$hashFile = Join-Path $OutDir ($name + '.zip.sha256')
Set-Content -LiteralPath $hashFile -Value ($hash + '  ' + (Split-Path -Leaf $zip)) -Encoding ASCII
Write-Host ('发布包: ' + $zip)
Write-Host ('大小  : ' + [math]::Round((Get-Item $zip).Length / 1MB, 2) + ' MB')
Write-Host ('SHA256: ' + $hash)