#Requires -Version 5.1
<#
.SYNOPSIS
  回归测试：静态解析 -> catalog 校验 -> 单元测试 -> CLI 契约与安全负向测试。
.DESCRIPTION
  设计原则：
  - 每一层独立可跳过，便于定位；
  - CLI 层只断言「退出码 + 输出卫生」，不依赖具体机器状态；
  - 任何写操作都被刻意挡在负向测试里（不加 --yes / 非管理员），确保回归不产生副作用。
.EXAMPLE
  .\scripts\regress.ps1
.EXAMPLE
  .\scripts\regress.ps1 -SkipUnit
#>
[CmdletBinding()]
param(
    [switch]$SkipStatic,
    [switch]$SkipUnit,
    [switch]$SkipCli,
    [switch]$AsJson
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$engine = Join-Path $root 'engine\winmedic.ps1'
$script:results = New-Object System.Collections.ArrayList

function Add-Result {
    param([string]$Layer, [string]$Name, [bool]$Ok, [string]$Detail = '')
    [void]$script:results.Add([pscustomobject]@{ layer = $Layer; name = $Name; ok = $Ok; detail = $Detail })
}

function Invoke-Engine {
    param([string[]]$EngineArgs)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $engine @EngineArgs 2>&1 | Out-String
    $sw.Stop()
    return @{ code = $LASTEXITCODE; text = $out; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
}

function Invoke-EngineDirect {
    <#  在同一会话内直接调用脚本，验证 --set / --ids 这类双横线写法（-File 模式会掩盖该问题）  #>
    param([string[]]$EngineArgs)
    $out = & $engine @EngineArgs *>&1 | Out-String
    return @{ code = $LASTEXITCODE; text = $out }
}

function Test-OutputHygiene {
    <#  禁止 emoji 与替代字符；禁止常见乱码迹象。  #>
    param([string]$Text)
    $problems = @()
    if ($Text -match '[\uD800-\uDFFF]') { $problems += 'surrogate' }
    if ($Text -match '[\u2600-\u27BF]') { $problems += 'symbol' }
    if ($Text -match '\uFFFD') { $problems += 'replacement-char' }
    if ($Text -match '锟斤拷') { $problems += 'gbk-mojibake' }
    return $problems
}

# ---------- 1 静态解析 ----------
if (-not $SkipStatic) {
    $bad = 0
    $files = Get-ChildItem -Path $root -Recurse -Filter *.ps1 -File | Where-Object { $_.FullName -notmatch '\\vendor\\' }
    foreach ($f in $files) {
        $errs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) {
            $bad++
            Add-Result 'static' ('解析 ' + $f.Name) $false (($errs | Select-Object -First 1).Message)
        }
    }
    Add-Result 'static' ('PowerShell 解析（' + @($files).Count + ' 个文件）') ($bad -eq 0) ('失败 ' + $bad)

    $r = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\validate-catalog.ps1') 2>&1 | Out-String
    Add-Result 'static' 'catalog 一致性' ($LASTEXITCODE -eq 0) ($r.Trim())
}

# ---------- 2 单元测试 ----------
if (-not $SkipUnit) {
    try {
        Import-Module Pester -MinimumVersion 5.0.0 -Force -ErrorAction Stop
        $u = Invoke-Pester -Path (Join-Path $root 'tests\pester') -PassThru -Output None
        Add-Result 'unit' ('Pester（' + $u.PassedCount + ' 通过 / ' + $u.FailedCount + ' 失败）') ($u.FailedCount -eq 0) ''
        $rt = Invoke-Pester -Path (Join-Path $root 'tests\routing') -PassThru -Output None
        Add-Result 'unit' ('路由（' + $rt.PassedCount + ' 通过 / ' + $rt.FailedCount + ' 失败）') ($rt.FailedCount -eq 0) ''
    } catch {
        Add-Result 'unit' 'Pester 不可用' $false $_.Exception.Message
    }
}

# ---------- 3 CLI 契约与安全负向 ----------
if (-not $SkipCli) {
    $isAdmin = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    $cases = @(
        @{ name = 'version'; args = @('version'); expect = 0 },
        @{ name = 'help'; args = @('help'); expect = 0 },
        @{ name = 'doctor'; args = @('doctor'); expect = 0 },
        @{ name = 'profile 查看'; args = @('profile'); expect = 0 },
        @{ name = 'journal 列表'; args = @('journal'); expect = 0 },
        @{ name = 'probe storage'; args = @('probe', '--set', 'storage'); expect = 0 },
        @{ name = 'probe 未知探针集 -> 2'; args = @('probe', '--set', 'nope'); expect = 2 },
        @{ name = 'probe mail'; args = @('probe', '--set', 'mail'); expect = 0 },
        @{ name = 'trend 记录'; args = @('trend', '--record', '--set', 'storage'); expect = 0 },
        @{ name = 'trend 报告'; args = @('trend'); expect = 0 },
        @{ name = 'remote 缺 target'; args = @('remote'); expect = 2 },
        @{ name = 'remote loopback'; args = @('remote', '--target', 'loopback-ci', '--via', 'local', '--set', 'storage'); expect = 0 },
        @{ name = 'remote 不可达'; args = @('remote', '--target', 'winmedic-no-such-host', '--timeout', '4'); expect = 8 },
        @{ name = 'probe workloads'; args = @('probe', '--set', 'workloads'); expect = 0 },
        @{ name = 'plan'; args = @('plan', '--set', 'storage'); expect = 0 },
        @{ name = 'apply 缺 --yes -> 2'; args = @('apply', '--ids', 'R1'); expect = 2 },
        @{ name = 'apply 缺 --ids -> 2'; args = @('apply', '--yes'); expect = 2 },
        @{ name = 'apply plan 不存在 -> 2'; args = @('apply', '--plan', 'nope.json', '--ids', 'R1', '--yes'); expect = 2 },
        @{ name = 'verify 缺 journal -> 2'; args = @('verify'); expect = 2 },
        @{ name = 'restore 缺 journal -> 2'; args = @('restore'); expect = 2 },
        @{ name = 'report'; args = @('report', '--set', 'storage'); expect = 0 },
        @{ name = 'explain 列表'; args = @('explain'); expect = 0 },
        @{ name = 'explain 单条'; args = @('explain', '--action', 'storage.hiberfil-off'); expect = 0 },
        @{ name = 'explain 未知动作 -> 2'; args = @('explain', '--action', 'no.such'); expect = 2 },
        @{ name = 'apply 非 standalone 动作 -> 2'; args = @('apply', '--action', 'storage.hiberfil-off', '--yes'); expect = 2 },
        @{ name = 'apply 未知动作 -> 2'; args = @('apply', '--action', 'no.such', '--yes'); expect = 2 },
        @{ name = 'summary'; args = @('summary'); expect = 0 },
        @{ name = 'plan 多域采集'; args = @('plan', '--set', 'intake'); expect = 0 },
        @{ name = 'diff 缺参数 -> 2'; args = @('diff', '--from', 'a.json'); expect = 2 },
        @{ name = 'diff 文件不存在 -> 2'; args = @('diff', '--from', 'a.json', '--to', 'b.json'); expect = 2 }
    )

    foreach ($c in $cases) {
        $r = Invoke-Engine -EngineArgs $c.args
        $ok = ($r.code -eq $c.expect)
        $detail = 'exit=' + $r.code + '（期望 ' + $c.expect + '，' + $r.seconds + 's）'
        if ($ok) {
            $hy = Test-OutputHygiene -Text $r.text
            if ($hy.Count -gt 0) { $ok = $false; $detail += ' 输出卫生问题: ' + ($hy -join ',') }
        }
        Add-Result 'cli' $c.name $ok $detail
    }

    # 非管理员时 apply 必须拒绝
    if (-not $isAdmin) {
        $r = Invoke-Engine -EngineArgs @('apply', '--ids', 'R1', '--yes')
        Add-Result 'cli' '非管理员 apply -> 3' ($r.code -eq 3) ('exit=' + $r.code)
    } else {
        Add-Result 'cli' '非管理员 apply -> 3' $true '当前为管理员会话，跳过该断言'
    }

    # 直接调用（--风格参数）
    $directCases = @(
        @{ name = '直接: probe --set storage'; args = @('probe', '--set', 'storage'); expect = 0 },
        @{ name = '直接: probe --set nope -> 2'; args = @('probe', '--set', 'nope'); expect = 2 },
        @{ name = '直接: plan --bogus -> 2'; args = @('plan', '--bogus'); expect = 2 },
        @{ name = '直接: explain --action'; args = @('explain', '--action', 'storage.hiberfil-off'); expect = 0 },
        @{ name = '直接: journal show'; args = @('journal', 'show'); expect = 0 },
        @{ name = '直接: apply --ids 缺 --yes -> 2'; args = @('apply', '--ids', 'R1'); expect = 2 }
    )
    foreach ($c in $directCases) {
        $r = Invoke-EngineDirect -EngineArgs $c.args
        $ok = ($r.code -eq $c.expect)
        Add-Result 'cli' $c.name $ok ('exit=' + $r.code + '（期望 ' + $c.expect + '）')
    }

    # JSON 契约：验证 stdout 能被外部消费（重定向到文件后解析）
    $jsonOut = Join-Path $env:TEMP ('wm-json-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json')
    & powershell -NoProfile -ExecutionPolicy Bypass -File $engine summary --set intake --json > $jsonOut 2>$null
    $okJson = $false; $detailJson = ''
    try {
        $j = Get-Content -LiteralPath $jsonOut -Raw -Encoding UTF8 | ConvertFrom-Json
        $dc = @($j.domains).Count
        $okJson = ($dc -ge 5 -and $j.host -ne $null)
        $detailJson = ('domains=' + $dc + ' recs=' + @($j.recommendations).Count)
    } catch { $detailJson = $_.Exception.Message }
    if (Test-Path -LiteralPath $jsonOut) { Remove-Item -LiteralPath $jsonOut -Force }
    Add-Result 'cli' 'JSON 契约: summary --json' $okJson $detailJson

    # 未知批次
    $r = Invoke-Engine -EngineArgs @('verify', '--journal', 'no-such-run')
    Add-Result 'cli' 'verify 未知批次 -> 2' ($r.code -eq 2) ('exit=' + $r.code)
}

# ---------- 汇总 ----------
$total = @($script:results).Count
$failed = @($script:results | Where-Object { -not $_.ok })
if ($AsJson) {
    [pscustomobject]@{ total = $total; failed = $failed.Count; results = $script:results } | ConvertTo-Json -Depth 6
    if ($failed.Count -gt 0) { exit 1 } else { exit 0 }
}

Write-Host ''
Write-Host '================ 回归结果 ================' 
foreach ($layer in @('static', 'unit', 'cli')) {
    $items = @($script:results | Where-Object { $_.layer -eq $layer })
    if ($items.Count -eq 0) { continue }
    $badCount = @($items | Where-Object { -not $_.ok }).Count
    $mark = if ($badCount -eq 0) { '[OK]  ' } else { '[FAIL]' }
    Write-Host ($mark + ' ' + $layer + '  ' + ($items.Count - $badCount) + '/' + $items.Count)
    foreach ($i in $items) {
        if ($i.ok) { continue }
        Write-Host ('        x ' + $i.name + '  ' + $i.detail) -ForegroundColor Red
    }
}
Write-Host ('----------------------------------------')
if ($failed.Count -eq 0) {
    Write-Host ('全部通过：' + $total + ' 项') -ForegroundColor Green
    exit 0
} else {
    Write-Host ('失败 ' + $failed.Count + ' / ' + $total + ' 项') -ForegroundColor Red
    exit 1
}