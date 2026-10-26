#Requires -Version 5.1
<#
.SYNOPSIS
  卸载 WinMedic。默认**保留**状态目录（隔离区/审计日志），除非显式 -PurgeState。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeState -Yes
#>
[CmdletBinding()]
param(
    [string]$Dest = '',
    [switch]$PurgeState,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
if (-not $Dest) { $Dest = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path $Dest)) { Write-Host ('未找到安装目录: ' + $Dest); exit 2 }
$metaPath = Join-Path $Dest 'install.json'
$meta = $null
if (Test-Path $metaPath) { $meta = Get-Content $metaPath -Raw | ConvertFrom-Json }

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -and (($userPath -split ';') -contains $Dest)) {
    $newPath = (@(($userPath -split ';') | Where-Object { $_ -and $_ -ne $Dest }) -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host ('已从用户 PATH 移除: ' + $Dest)
}

Remove-Item -LiteralPath $Dest -Recurse -Force
Write-Host ('已删除程序目录: ' + $Dest)

$stateCandidates = @((Join-Path $env:ProgramData 'cdrive'), (Join-Path $env:LOCALAPPDATA 'winmedic'))
foreach ($s in $stateCandidates) {
    if (-not (Test-Path $s)) { continue }
    if ($PurgeState) {
        if (-not $Yes) { Write-Host ('保留状态目录（未加 -Yes）: ' + $s) -ForegroundColor Yellow; continue }
        Remove-Item -LiteralPath $s -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ('已删除状态目录: ' + $s) -ForegroundColor Yellow
    } else {
        Write-Host ('已保留状态目录（含隔离区与审计日志）: ' + $s)
    }
}
Write-Host '卸载完成。'