#Requires -Version 5.1
<#
.SYNOPSIS
  发布推送：自动探测可用出口（直连 / 系统代理 / 常见端口）→ 推送 → ls-remote 校验。
.NOTES
  端口会漂移、代理可能被关：不要写死端口，也不要假设系统代理一定启用。
#>
[CmdletBinding()]
param(
    [string]$Remote = 'origin',
    [string]$Branch = 'main',
    [int]$Retries = 6,
    [int]$DelaySec = 15,
    [switch]$SkipProxySync
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$env:GIT_TERMINAL_PROMPT = '0'

function Test-Egress([string]$Proxy) {
    # 用真实仓库的 ls-remote 探测（比 curl github.com 可靠：301 也算通会误判）
    $url = (& git config --get ('remote.' + $Remote + '.url'))
    if (-not $url) { return $false }
    if ($Proxy) { $out = & git -c http.proxy=$Proxy -c https.proxy=$Proxy ls-remote --heads $url 2>&1 }
    else { $out = & git -c http.proxy= -c https.proxy= ls-remote --heads $url 2>&1 }
    return ($LASTEXITCODE -eq 0)
}

function Find-Egress {
    $cands = @()
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($ie -and $ie.ProxyEnable -eq 1 -and $ie.ProxyServer) {
        $cands += ('http://' + ($ie.ProxyServer -replace '^https?://', ''))
    }
    $gitProxy = (& git config --get http.proxy 2>$null)
    if ($gitProxy) { $cands += $gitProxy }
    foreach ($p in 7897, 7890, 10808, 10809, 8136, 50575) { $cands += ('http://127.0.0.1:' + $p) }
    $cands = @($cands | Where-Object { $_ } | Select-Object -Unique)
    foreach ($c in $cands) { if (Test-Egress -Proxy $c) { return @{ kind = 'proxy'; value = $c } } }
    if (Test-Egress -Proxy '') { return @{ kind = 'direct'; value = '' } }
    return $null
}

$egress = Find-Egress
if (-not $egress) {
    Write-Host '没有可用出口：直连与常见代理端口都到不了 GitHub。' -ForegroundColor Red
    Write-Host '  - 检查代理软件是否在运行 / 系统代理是否启用' -ForegroundColor Yellow
    Write-Host '  - 本次未推送；提交与 tag 都在本地，网络恢复后重跑本脚本即可' -ForegroundColor Yellow
    exit 3
}
if ($egress.kind -eq 'proxy') {
    Write-Host ('出口: 代理 ' + $egress.value) -ForegroundColor Green
    $env:HTTP_PROXY = $egress.value; $env:HTTPS_PROXY = $egress.value
    & git config --global http.proxy $egress.value | Out-Null
    & git config --global https.proxy $egress.value | Out-Null
} else {
    Write-Host '出口: 直连' -ForegroundColor Green
    & git config --global --unset http.proxy 2>$null | Out-Null
    & git config --global --unset https.proxy 2>$null | Out-Null
}

$local = (& git rev-parse HEAD).Trim()
Write-Host ('本地 HEAD : ' + $local.Substring(0, 7))
for ($i = 1; $i -le $Retries; $i++) {
    $out = (& git push $Remote $Branch 2>&1 | Out-String)
    if ($out -match 'non-fast-forward|fetch first') { Write-Host '远端有本地没有的提交，先 git pull --rebase。' -ForegroundColor Yellow; exit 2 }
    $remoteHead = (& git ls-remote $Remote ('refs/heads/' + $Branch) 2>$null | Select-Object -First 1)
    if ($remoteHead -and $remoteHead.Split()[0] -eq $local) {
        Write-Host ('main 已同步（第 ' + $i + ' 次）') -ForegroundColor Green
        $null = (& git push $Remote --tags 2>&1 | Out-String)
        Write-Host ('tags 推送: ' + $(if ($LASTEXITCODE -eq 0) { '成功' } else { '失败（可用 --force 重推）' }))
        exit 0
    }
    Write-Host ('第 ' + $i + ' 次未成功，' + $DelaySec + ' 秒后重试') -ForegroundColor Yellow
    Start-Sleep -Seconds $DelaySec
}
Write-Host '多次重试仍未同步。' -ForegroundColor Red
exit 1