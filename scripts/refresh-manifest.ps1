$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @()
foreach ($sub in @('', 'lib', 'probes', 'mcp')) {
    $dir = if ($sub) { Join-Path (Join-Path $root 'engine') $sub } else { Join-Path $root 'engine' }
    if (-not (Test-Path $dir)) { continue }
    foreach ($f in (Get-ChildItem $dir -Filter '*.ps1' -File)) { $files += (if ($sub) { $sub + '/' + $f.Name } else { $f.Name }) }
}
$files = $files | Sort-Object
Set-Content -LiteralPath (Join-Path (Join-Path $root 'engine') 'MANIFEST.txt') -Value ($files -join "`n") -Encoding UTF8
Write-Host ('清单已更新：' + $files.Count + ' 个文件')