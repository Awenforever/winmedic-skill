#Requires -Version 5.1
<#
.SYNOPSIS
  安装 WinMedic（默认当前用户，无需管理员）。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Dest 'D:\Tools\WinMedic' -AddToPath
#>
[CmdletBinding()]
param(
    [string]$Dest = (Join-Path $env:LOCALAPPDATA 'Programs\WinMedic'),
    [switch]$AddToPath,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$ver = (Get-Content (Join-Path $src 'VERSION') -Raw).Trim()

if (-not (Test-Path (Join-Path $src 'engine\winmedic.ps1'))) { throw '安装包不完整：缺少 engine\winmedic.ps1' }
if ((Test-Path $Dest) -and -not $Force) {
    $old = if (Test-Path (Join-Path $Dest 'install.json')) { (Get-Content (Join-Path $Dest 'install.json') -Raw | ConvertFrom-Json).version } else { '未知' }
    throw ('目标已存在（已安装版本 ' + $old + '）：' + $Dest + '。升级请加 -Force')
}

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$dirs = @('engine', 'catalog', 'playbooks', 'cases', 'docs')
$files = @('SKILL.md', 'README.md', 'README.en.md', 'LICENSE', 'VERSION', 'CHANGELOG.md', 'playbook-index.md', 'SECURITY.md', 'CONTRIBUTING.md', 'install.ps1', 'uninstall.ps1')
$blocked = @()
foreach ($d in $dirs) {
    $s = Join-Path $src $d
    if (-not (Test-Path $s)) { continue }
    $t = Join-Path $Dest $d
    if (Test-Path $t) { Remove-Item $t -Recurse -Force }
    try { Copy-Item -LiteralPath $s -Destination $t -Recurse -Force -ErrorAction Stop }
    catch {
        # 安全软件可能按内容拦截个别文件；能拷的先拷，最后统一提示
        if (Test-Path $s) {
            foreach ($f in (Get-ChildItem $s -Recurse -File)) {
                $rel = $f.FullName.Substring($s.Length).TrimStart('\')
                $dstFile = Join-Path $t $rel
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dstFile) | Out-Null
                try { Copy-Item -LiteralPath $f.FullName -Destination $dstFile -Force -ErrorAction Stop } catch { $blocked += $rel }
            }
        }
    }
}
foreach ($f in $files) {
    $s = Join-Path $src $f
    if (Test-Path $s) { Copy-Item -LiteralPath $s -Destination (Join-Path $Dest $f) -Force }
}

$cmd = Join-Path $Dest 'winmedic.cmd'
$cmdBody = @('@echo off', 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0engine\winmedic.ps1" %*') -join "`r`n"
Set-Content -LiteralPath $cmd -Value $cmdBody -Encoding ASCII

$meta = [ordered]@{ version = $ver; installedAt = (Get-Date).ToString('o'); dest = $Dest; source = $src }
($meta | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $Dest 'install.json') -Encoding UTF8

if ($AddToPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if (($userPath -split ';') -notcontains $Dest) {
        $newPath = if ($userPath.Trim()) { $userPath.TrimEnd(';') + ';' + $Dest } else { $Dest }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host ('已加入用户 PATH: ' + $Dest)
    }
}

$remoteFile = Join-Path (Join-Path $Dest 'engine\lib') 'Remote.ps1'
$remoteLen = 0
if (Test-Path -LiteralPath $remoteFile) {
    try { $remoteLen = (Get-Content -LiteralPath $remoteFile -Raw -ErrorAction Stop).Length } catch { $remoteLen = 0 }
}
if ($remoteLen -le 0) {
    Write-Host ''
    Write-Host '注意：engine/lib/Remote.ps1 缺失或被安全软件拦截（读到的内容为空）。' -ForegroundColor Yellow
    Write-Host '  - 远端功能（remote / remote-probe / remote-apply）将不可用，其它功能正常' -ForegroundColor Yellow
    Write-Host ('  - 处理：把安装目录加入杀毒软件信任区后重新运行本安装脚本：' + $Dest) -ForegroundColor Yellow
    if ($blocked.Count -gt 0) { Write-Host ('  - 被拦截文件：' + (($blocked | Select-Object -Unique) -join ', ')) -ForegroundColor Yellow }
    Write-Host ''
}

Write-Host ('已安装 WinMedic ' + $ver + ' -> ' + $Dest)
Write-Host ('入口: ' + $cmd)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dest 'engine\winmedic.ps1') doctor | Out-Host
Write-Host '安装自检完成。'