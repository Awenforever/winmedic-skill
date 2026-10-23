#Requires -Version 5.1
<#
.SYNOPSIS
  发布前环境自愈：把 git 的 http.proxy 同步到当前系统代理（端口会漂移）。
.NOTES
  只改 http.proxy / https.proxy 两项，不动其它 git 配置。
#>
[CmdletBinding()]
param([switch]$Show)

$ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
$proxy = $null
if ($ie -and $ie.ProxyEnable -eq 1 -and $ie.ProxyServer) {
    $proxy = $ie.ProxyServer
    if ($proxy -notmatch '://') { $proxy = 'http://' + $proxy }
}

$current = git config --global --get http.proxy 2>$null
Write-Host ('当前 git http.proxy : ' + $current)
Write-Host ('系统代理             : ' + $(if ($proxy) { $proxy } else { '(未启用)' }))

if ($Show) { exit 0 }

if (-not $proxy) {
    Write-Host '系统代理未启用，跳过。若需要直连请手动设置 git 代理。'
    exit 0
}

if ($current -ne $proxy) {
    git config --global http.proxy $proxy
    git config --global https.proxy $proxy
    Write-Host ('已更新为: ' + $proxy) -ForegroundColor Green
} else {
    Write-Host '已是当前值，无需修改。'
}

Write-Host '验证 GitHub 连通性...'
$out = git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=10 ls-remote https://github.com/Awenforever/winmedic-skill.git HEAD 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host 'GitHub 可访问。' -ForegroundColor Green } else { Write-Host ('GitHub 访问失败: ' + ($out -join ' ')) -ForegroundColor Yellow }