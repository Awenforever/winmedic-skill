#Requires -Version 5.1
<#
.SYNOPSIS
  安装到宿主（DSH）之后的验收：技能可解析、MCP 可握手、编码正确、版本一致。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\verify-host.ps1
  powershell -ExecutionPolicy Bypass -File .\scripts\verify-host.ps1 -Json
#>
[CmdletBinding()]
param(
    [string]$SkillDir = (Join-Path $env:USERPROFILE '.dsh\skills\winmedic'),
    [string]$ProfileDir = (Join-Path $env:USERPROFILE '.dsh\profiles'),
    [switch]$Json
)
$ErrorActionPreference = 'Continue'
$checks = @()
function Add-Check([string]$name, [bool]$ok, [string]$detail = '') {
    $script:checks += [pscustomobject]@{ name = $name; ok = $ok; detail = $detail }
}

# 1 目录与关键文件
$skillMd = Join-Path $SkillDir 'SKILL.md'
$engine = Join-Path $SkillDir 'engine\winmedic.ps1'
$remote = Join-Path $SkillDir 'engine\lib\Remote.ps1'
Add-Check 'SKILL.md 存在' (Test-Path $skillMd) $skillMd
Add-Check 'engine 存在' (Test-Path $engine) $engine
$remoteLen = 0
if (Test-Path $remote) { try { $remoteLen = (Get-Content -LiteralPath $remote -Raw -ErrorAction Stop).Length } catch { $remoteLen = 0 } }
Add-Check 'Remote.ps1 可读（未被安全软件拦截）' ($remoteLen -gt 0) $(if ($remoteLen -gt 0) { 'ok' } else { '为空或缺失：远端功能会降级' })

# 2 版本一致
$installedVer = ''
$vFile = Join-Path $SkillDir 'VERSION'
if (Test-Path $vFile) { $installedVer = (Get-Content $vFile -Raw).Trim() }
$engineVer = ''
if (Test-Path $engine) { $engineVer = ((& powershell -NoProfile -ExecutionPolicy Bypass -File $engine version 2>$null | Out-String).Trim() -replace '^winmedic\s+', '') }
Add-Check 'VERSION 与引擎版本一致' ($installedVer -and $installedVer -eq $engineVer) ($installedVer + ' / ' + $engineVer)

# 3 frontmatter 合法性（宿主解析契约）
$fmOk = $false; $fmDetail = ''
if (Test-Path $skillMd) {
    $lines = Get-Content $skillMd -Encoding UTF8
    $hasName = $false; $hasDesc = $false; $bad = @()
    if ($lines.Count -gt 1 -and $lines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '---') { break }
            $line = $lines[$i]
            if ($line -match '^name:\s*\S') { $hasName = $true }
            if ($line -match '^description:\s*\S') { $hasDesc = $true }
            if ($line -match '^[A-Za-z_][\w-]*:\s*(.+)$') {
                $val = $Matches[1].Trim()
                if ($val -and -not $val.StartsWith('"') -and -not $val.StartsWith("'") -and $val.Contains(': ')) { $bad += $line.Substring(0, [Math]::Min(30, $line.Length)) }
            }
        }
    }
    $fmOk = ($hasName -and $hasDesc -and $bad.Count -eq 0)
    $fmDetail = if ($fmOk) { 'name/description 就绪，无裸冒号空格' } else { ('name=' + $hasName + ' desc=' + $hasDesc + ' 风险行=' + $bad.Count) }
}
Add-Check 'frontmatter 可被 YAML 解析' $fmOk $fmDetail

# 4 引擎自检
$doctorOk = $false
if (Test-Path $engine) {
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $engine doctor 2>&1
    $doctorOk = ($LASTEXITCODE -eq 0)
}
Add-Check 'doctor 通过' $doctorOk

# 5 MCP stdio 握手 + 编码
$mcp = Join-Path $SkillDir 'engine\mcp\winmedic-mcp.ps1'
$mcpOk = $false; $mcpDetail = ''; $toolCount = 0
if (Test-Path $mcp) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $mcp + '"'
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false, $true)
        $p = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Milliseconds 700
        $p.StandardInput.WriteLine('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify-host","version":"1"}}}')
        $p.StandardInput.Flush()
        $init = $p.StandardOutput.ReadLine() | ConvertFrom-Json
        $p.StandardInput.WriteLine('{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
        $p.StandardInput.Flush()
        $list = $p.StandardOutput.ReadLine() | ConvertFrom-Json
        $toolCount = @($list.result.tools).Count
        $p.StandardInput.WriteLine('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"winmedic_doctor","arguments":{}}}')
        $p.StandardInput.Flush()
        $call = $p.StandardOutput.ReadLine()
        $p.StandardInput.Close()
        Start-Sleep -Milliseconds 200
        if (-not $p.HasExited) { $p.Kill() }
        $mcpOk = ($init.result.serverInfo.name -eq 'winmedic') -and ($toolCount -ge 10) -and ($call -match '环境自检')
        $mcpDetail = ('server=' + $init.result.serverInfo.name + ' tools=' + $toolCount + ' 中文=' + [bool]($call -match '环境自检'))
    } catch { $mcpDetail = $_.Exception.Message }
}
Add-Check 'MCP 握手与 UTF-8 输出' $mcpOk $mcpDetail

# 6 DSH profile 注册
$registered = @()
if (Test-Path $ProfileDir) {
    Get-ChildItem $ProfileDir -Directory | ForEach-Object {
        $y = Join-Path $_.FullName 'cordis.patch.yml'
        if ((Test-Path $y) -and (Select-String -Path $y -Pattern 'mcp-winmedic' -Quiet)) { $registered += $_.Name }
    }
}
Add-Check 'MCP 已注册到 DSH profile' (@($registered).Count -gt 0) (($registered -join ', '))

$fail = @($checks | Where-Object { -not $_.ok })
if ($Json) {
    $checks | ConvertTo-Json -Depth 4
    if ($fail.Count -gt 0) { exit 1 } else { exit 0 }
}
foreach ($c in $checks) {
    $tag = if ($c.ok) { '[PASS]' } else { '[FAIL]' }
    Write-Host ($tag + ' ' + $c.name + $(if ($c.detail) { '  (' + $c.detail + ')' } else { '' }))
}
Write-Host ''
Write-Host ('结果: ' + (@($checks).Count - $fail.Count) + '/' + @($checks).Count + ' 通过')
if ($fail.Count -gt 0) { exit 1 } else { exit 0 }