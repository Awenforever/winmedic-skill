#Requires -Version 5.1
<#
.SYNOPSIS
  发布：同步 git 代理 -> 从凭据管理器取 token -> 创建仓库 -> push。
.NOTES
  不写入任何明文凭据；token 由 git credential fill 在内存中取得。
#>
[CmdletBinding()]
param(
    [string]$Owner = 'Awenforever',
    [string]$Repo = 'winmedic-skill',
    [string]$Description = 'Windows 电脑维修 Agent Skill：诊断/清理/迁移，只读优先、可回滚、带证据链。',
    [switch]$SkipCreate
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 1) 代理
$ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
$proxy = $null
if ($ie -and $ie.ProxyEnable -eq 1 -and $ie.ProxyServer) {
    $proxy = $ie.ProxyServer
    if ($proxy -notmatch '://') { $proxy = 'http://' + $proxy }
}
if ($proxy) {
    git config --global http.proxy $proxy
    git config --global https.proxy $proxy
    Write-Host ('代理: ' + $proxy)
}

# 2) 取 token
$inputText = "protocol=https`nhost=github.com`n`n"
$cred = $inputText | git credential fill 2>$null
$token = $null
foreach ($line in $cred) { if ($line -like 'password=*') { $token = $line.Substring(9) } }
if (-not $token) { throw '无法从凭据管理器取得 GitHub token' }
Write-Host '已取得 token（不显示内容）'

$headers = @{ Authorization = ('token ' + $token); 'User-Agent' = 'winmedic-publish'; Accept = 'application/vnd.github+json' }
$apiArgs = @{ Headers = $headers; ErrorAction = 'Stop' }
if ($proxy) { $apiArgs['Proxy'] = $proxy }

# 3) 创建仓库
if (-not $SkipCreate) {
    $exists = $false
    try {
        Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $Owner + '/' + $Repo) @apiArgs | Out-Null
        $exists = $true
    } catch { $exists = $false }
    if ($exists) {
        Write-Host ('仓库已存在: ' + $Owner + '/' + $Repo)
    } else {
        $body = @{ name = $Repo; description = $Description; private = $false; has_issues = $true; has_wiki = $false; auto_init = $false } | ConvertTo-Json
        try {
            Invoke-RestMethod -Uri 'https://api.github.com/user/repos' -Method Post -Body $body -ContentType 'application/json' @apiArgs | Out-Null
            Write-Host ('仓库已创建: https://github.com/' + $Owner + '/' + $Repo) -ForegroundColor Green
        } catch {
            Write-Host ('创建失败: ' + $_.Exception.Message) -ForegroundColor Yellow
            Write-Host '若 token 缺少 repo scope，请手动建仓后执行: .\scripts\publish.ps1 -SkipCreate'
            throw
        }
    }
}

# 4) 远端与推送
$remoteUrl = 'https://github.com/' + $Owner + '/' + $Repo + '.git'
$existing = git remote 2>$null
if ($existing -contains 'origin') { git remote set-url origin $remoteUrl } else { git remote add origin $remoteUrl }
git push -u origin main 2>&1 | Out-String | Write-Host
git push --tags 2>&1 | Out-String | Write-Host
Write-Host ('完成: ' + $remoteUrl) -ForegroundColor Green