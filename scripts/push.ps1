#Requires -Version 5.1
<#
.SYNOPSIS
  发布推送：同步系统代理（端口会漂移）→ 推送 main/tags → 用 ls-remote 校验真实同步。
.NOTES
  不要再用 -c http.proxy= 手工指定端口：端口轮换后必然失败。
#>
[CmdletBinding()]
param(
    [string]$Remote = 'origin',
    [string]$Branch = 'main',
    [int]$Retries = 8,
    [int]$DelaySec = 20,
    [switch]$SkipProxySync
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$env:GIT_TERMINAL_PROMPT = '0'

if (-not $SkipProxySync) {
    $setup = Join-Path $PSScriptRoot 'gh-setup.ps1'
    if (Test-Path $setup) { & powershell -NoProfile -ExecutionPolicy Bypass -File $setup | Out-Host }
}

$local = (& git rev-parse HEAD).Trim()
Write-Host ('本地 HEAD : ' + $local.Substring(0, 7))

for ($i = 1; $i -le $Retries; $i++) {
    $out = (& git push $Remote $Branch 2>&1 | Out-String)
    $code = $LASTEXITCODE
    if ($code -ne 0 -and $out -match 'non-fast-forward|fetch first') {
        Write-Host '远端有本地没有的提交，先 git pull --rebase 再推送。' -ForegroundColor Yellow
        exit 2
    }
    $remoteHead = (& git ls-remote $Remote ('refs/heads/' + $Branch) 2>$null | Select-Object -First 1)
    if ($remoteHead -and $remoteHead.Split()[0] -eq $local) {
        Write-Host ('main 已同步（第 ' + $i + ' 次尝试）') -ForegroundColor Green
        $null = (& git push $Remote --tags 2>&1 | Out-String)
        $tagCode = $LASTEXITCODE
        Write-Host ('tags 推送: ' + $(if ($tagCode -eq 0) { '成功' } else { '失败（可用 --force 重推）' }))
        exit 0
    }
    Write-Host ('第 ' + $i + ' 次未成功，' + $DelaySec + ' 秒后重试') -ForegroundColor Yellow
    Start-Sleep -Seconds $DelaySec
}
Write-Host '多次重试仍未同步：先跑 scripts\gh-setup.ps1 看代理，再手工检查 git remote。' -ForegroundColor Red
exit 1