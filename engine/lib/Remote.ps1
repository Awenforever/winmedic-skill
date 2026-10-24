#Requires -Version 5.1
<#
.SYNOPSIS
  远程会话层：把只读探针送到远端执行，把证据带回来。
.DESCRIPTION
  设计约束：
    - 只用既有 SSH 信任（BatchMode，绝不交互式要密码）
    - 默认只读：本版本不支持远程 apply
    - 远端 findings 一律打 origin 标记，本地 apply 必须拒绝远端条目
    - 远端临时目录默认清理
#>

function Get-RemoteTargetProfile {
    <#  纯函数：解析 target。返回 @{ valid; alias; user; host; isLoopback; error }  #>
    param([string]$Target = '')
    $p = @{ valid = $false; alias = ''; user = ''; host = ''; isLoopback = $false; error = '' }
    if (-not $Target) { $p.error = 'target 不能为空'; return $p }
    $t = $Target.Trim()
    $p.alias = $t
    if ($t -match '^(?<u>[^@\s]+)@(?<h>[^@\s]+)$') {
        $p.user = $Matches['u']
        $p.host = $Matches['h']
    } elseif ($t -match '^[A-Za-z0-9._-]+$') {
        $p.host = $t
    } else {
        $p.error = ('无法解析 target: ' + $t)
        return $p
    }
    $loopbacks = @('localhost', '127.0.0.1', '::1', '.')
    if ($loopbacks -contains $p.host.ToLowerInvariant()) { $p.isLoopback = $true }
    if ($env:COMPUTERNAME -and $p.host.Equals($env:COMPUTERNAME, [StringComparison]::OrdinalIgnoreCase)) { $p.isLoopback = $true }
    $p.valid = $true
    return $p
}

function Set-FindingsOrigin {
    <#  纯函数：给每个 probe 打 origin 标记（已有则保留）。返回新对象。  #>
    param($Findings = $null, [string]$Origin = 'local')
    if (-not $Findings) { return $Findings }
    foreach ($pr in @($Findings.probes)) {
        if (-not $pr) { continue }
        if ($pr.PSObject.Properties.Name -contains 'origin' -and $pr.origin) { continue }
        $pr | Add-Member -NotePropertyName 'origin' -NotePropertyValue $Origin -Force
    }
    return $Findings
}

function Get-RemoteFindingsName {
    <#  纯函数：远端回传文件的落库名。  #>
    param([string]$Alias = '', [string]$Set = 'storage')
    $safe = ($Alias -replace '[^A-Za-z0-9._-]', '_')
    if (-not $safe) { $safe = 'unknown' }
    return ('remote-' + $safe + '-' + $Set + '-findings.json')
}

function New-RemoteStageScript {
    <#  纯函数：生成远端引导脚本（不执行）。  #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RunId,
        [string]$Set = 'intake',
        [string]$OutFile = ''
    )
    if (-not $OutFile) { $OutFile = Join-Path $Root ($Set + '-findings.json') }
    $lines = @(
        '$ErrorActionPreference = ''Stop''',
        "Set-ExecutionPolicy -Scope Process Bypass -Force -ErrorAction SilentlyContinue",
        "[Console]::OutputEncoding = [Text.Encoding]::UTF8",
        ('$env:CDRIVE_HOME = ''' + (Join-Path $Root 'cdrive') + "'"),
        ('& ''' + (Join-Path $Root 'engine\winmedic.ps1') + ''' probe --set ' + $Set + ' --out ''' + $OutFile + "'"),
        'exit $LASTEXITCODE'
    )
    return ($lines -join [Environment]::NewLine)
}

function Format-RemotePathArg {
    <#
      远端命令里的路径参数：无空格时裸写（cmd 不剥单引号，裸写最稳）；
      含空格时用双引号兜底。
    #>
    param([string]$Path = '')
    if (-not $Path) { return '' }
    if ($Path -match ' ') { return ('"' + $Path + '"') }
    return $Path
}

function New-RemoteBundle {
    <#  打包最小运行集（engine/catalog/VERSION/SKILL.md），返回 zip 路径。  #>
    param([Parameter(Mandatory)][string]$RepoRoot, [string]$OutZip = '')
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('winmedic-stage-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    foreach ($item in @('engine', 'catalog', 'VERSION', 'SKILL.md')) {
        $src = Join-Path $RepoRoot $item
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $stage -Recurse -Force }
    }
    if (-not $OutZip) { $OutZip = Join-Path ([IO.Path]::GetTempPath()) ('winmedic-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.zip') }
    if (Test-Path -LiteralPath $OutZip) { Remove-Item -LiteralPath $OutZip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutZip -Force
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    return $OutZip
}

function Invoke-RemoteShell {
    <#
      执行一条远端命令。返回 @{ ok; exit; text }。
      注意：PS 5.1 下原生命令写 stderr 会产生 NativeCommandError，
      在 ErrorActionPreference=Stop 时会终止进程（exit 1）。这里必须局部降级。
    #>
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$Command, [int]$TimeoutSec = 30)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $argList = @('-o', 'BatchMode=yes', '-o', ('ConnectTimeout=' + $TimeoutSec), '-o', 'StrictHostKeyChecking=accept-new', $Target, $Command)
        $out = & ssh @argList 2>&1 | Out-String
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 255 }
        return @{ ok = ($code -eq 0); exit = $code; text = $out.Trim() }
    } catch {
        return @{ ok = $false; exit = 255; text = $_.Exception.Message }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Test-RemoteReachable {
    param([Parameter(Mandatory)][string]$Target, [int]$TimeoutSec = 8)
    $r = Invoke-RemoteShell -Target $Target -Command 'echo winmedic-ok' -TimeoutSec $TimeoutSec
    return @{ ok = ($r.ok -and $r.text -match 'winmedic-ok'); text = $r.text }
}

function Get-RemoteStateDir {
    $d = Join-Path (Get-CdriveStateDir) 'state'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    return $d
}

function Import-RemoteFindings {
    <#  回传文件落库并打 origin 标记，返回本地路径。  #>
    param(
        [Parameter(Mandatory)][string]$RemoteFile,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$Set
    )
    if (-not (Test-Path -LiteralPath $RemoteFile)) { throw ('回传文件不存在: ' + $RemoteFile) }
    $name = Get-RemoteFindingsName -Alias $Alias -Set $Set
    $dest = Join-Path (Get-RemoteStateDir) $name
    Copy-Item -LiteralPath $RemoteFile -Destination $dest -Force
    $f = Get-Content -LiteralPath $dest -Raw -Encoding UTF8 | ConvertFrom-Json
    $f = Set-FindingsOrigin -Findings $f -Origin ('remote:' + $Alias)
    ($f | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $dest -Encoding UTF8
    return $dest
}

function Invoke-RemoteSession {
    <#
      编排一次远程只读采集。
      -Via 'local' 时走 loopback（把远端步骤在本机临时目录执行），用于 CI 与自测。
      返回 @{ ok; exitCode; findingsPath; runId; seconds; detail }
    #>
    param(
        [Parameter(Mandatory)][string]$Target,
        [string]$Set = 'intake',
        [ValidateSet('ssh', 'local')][string]$Via = 'ssh',
        [int]$TimeoutSec = 300,
        [string]$RepoRoot = '',
        [switch]$Keep
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $runId = 'rem-' + (Get-Date).ToString('yyyyMMdd-HHmmss')
    if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
    $profile = Get-RemoteTargetProfile -Target $Target
    if (-not $profile.valid) { return @{ ok = $false; exitCode = 8; detail = $profile.error; runId = $runId } }

    if ($Via -eq 'local') {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('winmedic-' + $runId)
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        foreach ($item in @('engine', 'catalog', 'VERSION')) {
            $src = Join-Path $RepoRoot $item
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $root -Recurse -Force }
        }
        $outFile = Join-Path $root ($Set + '-findings.json')
        $env:CDRIVE_HOME = Join-Path $root 'cdrive'
        try {
            $null = & (Join-Path $root 'engine\winmedic.ps1') probe --set $Set --out $outFile 2>&1
        } finally {
            Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path -LiteralPath $outFile)) { return @{ ok = $false; exitCode = 8; detail = 'loopback 未生成 findings'; runId = $runId } }
        $dest = Import-RemoteFindings -RemoteFile $outFile -Alias ($profile.alias + '-loopback') -Set $Set
        if (-not $Keep) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        $sw.Stop()
        return @{ ok = $true; exitCode = 0; findingsPath = $dest; runId = $runId; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); detail = 'loopback' }
    }

    $reach = Test-RemoteReachable -Target $profile.alias
    if (-not $reach.ok) {
        $sw.Stop()
        return @{ ok = $false; exitCode = 8; runId = $runId; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); detail = ('不可达: ' + $reach.text) }
    }

    $sw2 = [Diagnostics.Stopwatch]::StartNew()
    $bundle = $null
    $localOut = $null
    try {
        $rTemp = Invoke-RemoteShell -Target $profile.alias -Command 'cmd /c echo %TEMP%'
        if (-not $rTemp.ok -or -not $rTemp.text) {
            return @{ ok = $false; exitCode = 8; runId = $runId; detail = ('无法获取远端 TEMP: ' + $rTemp.text) }
        }
        $remoteTemp = ''
        if ($rTemp.text) { $remoteTemp = (($rTemp.text.Trim() -split "\n")[0]) }
        $remoteTemp = $remoteTemp.Trim().Trim([char]34).Trim([char]39).TrimEnd([char]92).Trim()
        if ($remoteTemp -notmatch '^[A-Za-z]:\\') {
            return @{ ok = $false; exitCode = 8; runId = $runId; detail = ('远端 TEMP 无法解析: [' + $rTemp.text + ']') }
        }
        $remoteDir = $remoteTemp + '\winmedic-' + $runId
        $mk = Invoke-RemoteShell -Target $profile.alias -Command ('powershell -NoProfile -Command New-Item -ItemType Directory -Force -Path ' + (Format-RemotePathArg $remoteDir))
        if (-not $mk.ok) { return @{ ok = $false; exitCode = 8; runId = $runId; detail = ('无法创建远端目录: ' + $mk.text) } }

        $bundle = New-RemoteBundle -RepoRoot $RepoRoot
        $remoteZip = $remoteDir + '\bundle.zip'
        & scp -o BatchMode=yes $bundle ($profile.alias + ':' + ($remoteZip -replace '\\', '/')) 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return @{ ok = $false; exitCode = 8; runId = $runId; detail = '上传 bundle 失败（scp）' } }

        $expand = Invoke-RemoteShell -Target $profile.alias -Command ('powershell -NoProfile -Command Expand-Archive -LiteralPath ' + (Format-RemotePathArg $remoteZip) + ' -DestinationPath ' + (Format-RemotePathArg $remoteDir) + ' -Force')
        if (-not $expand.ok) { return @{ ok = $false; exitCode = 8; runId = $runId; detail = ('远端解压失败: ' + $expand.text) } }

        $stageLocal = Join-Path ([IO.Path]::GetTempPath()) ('stage-' + $runId + '.ps1')
        $stageText = New-RemoteStageScript -Root $remoteDir -RunId $runId -Set $Set
        Set-Content -LiteralPath $stageLocal -Value $stageText -Encoding UTF8
        $remoteStage = $remoteDir + '\stage.ps1'
        & scp -o BatchMode=yes $stageLocal ($profile.alias + ':' + ($remoteStage -replace '\\', '/')) 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return @{ ok = $false; exitCode = 8; runId = $runId; detail = '上传引导脚本失败（scp）' } }

        $run = Invoke-RemoteShell -Target $profile.alias -Command ('powershell -NoProfile -ExecutionPolicy Bypass -File ' + (Format-RemotePathArg $remoteStage)) -TimeoutSec $TimeoutSec
        $remoteOut = $remoteDir + '\' + $Set + '-findings.json'
        $localOut = Join-Path ([IO.Path]::GetTempPath()) ('pull-' + $runId + '.json')
        & scp -o BatchMode=yes ($profile.alias + ':' + ($remoteOut -replace '\\', '/')) $localOut 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $hint = '远端探测可能失败或超时'
            if ($run.text) { $hint = $hint + '；远端输出: ' + $run.text }
            return @{ ok = $false; exitCode = 8; runId = $runId; detail = $hint }
        }

        $dest = Import-RemoteFindings -RemoteFile $localOut -Alias $profile.alias -Set $Set
        $sw.Stop()
        return @{ ok = $true; exitCode = 0; findingsPath = $dest; runId = $runId; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); detail = ('remote=' + $remoteDir); remoteOutput = $run.text }
    } catch {
        return @{ ok = $false; exitCode = 8; runId = $runId; detail = ('远程会话异常: ' + $_.Exception.Message) }
    } finally {
        if ($bundle -and (Test-Path -LiteralPath $bundle)) { Remove-Item -LiteralPath $bundle -Force -ErrorAction SilentlyContinue }
        if (-not $Keep) {
            try { $null = Invoke-RemoteShell -Target $profile.alias -Command ('powershell -NoProfile -Command Remove-Item -LiteralPath ' + (Format-RemotePathArg $remoteDir) + ' -Recurse -Force -ErrorAction SilentlyContinue') -TimeoutSec 30 } catch { }
        }
    }
}

function New-RemoteStage {
    <#  上传最小运行集到远端临时目录，返回 @{ ok; dir; temp }。  #>
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$RepoRoot, [int]$TimeoutSec = 120)
    $rTemp = Invoke-RemoteShell -Target $Target -Command 'cmd /c echo %TEMP%'
    if (-not $rTemp.ok -or -not $rTemp.text) { return @{ ok = $false; detail = ('无法获取远端 TEMP: ' + $rTemp.text) } }
    $tmp = (($rTemp.text.Trim() -split "\n")[0]).Trim().Trim([char]34).Trim([char]39).TrimEnd([char]92).Trim()
    if ($tmp -notmatch '^[A-Za-z]:\\') { return @{ ok = $false; detail = ('远端 TEMP 无法解析: [' + $rTemp.text + ']') } }
    $dir = $tmp + '\winmedic-' + (Get-Date).ToString('yyyyMMdd-HHmmss')
    $mk = Invoke-RemoteShell -Target $Target -Command ('powershell -NoProfile -Command New-Item -ItemType Directory -Force -Path ' + (Format-RemotePathArg $dir))
    if (-not $mk.ok) { return @{ ok = $false; detail = ('建目录失败: ' + $mk.text) } }
    $bundle = New-RemoteBundle -RepoRoot $RepoRoot
    & scp -o BatchMode=yes $bundle ($Target + ':' + (($dir + '\bundle.zip') -replace '\\', '/')) 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $bundle -Force -ErrorAction SilentlyContinue; return @{ ok = $false; detail = '上传 bundle 失败' } }
    $ex = Invoke-RemoteShell -Target $Target -Command ('powershell -NoProfile -Command Expand-Archive -LiteralPath ' + (Format-RemotePathArg ($dir + '\bundle.zip')) + ' -DestinationPath ' + (Format-RemotePathArg $dir) + ' -Force')
    Remove-Item -LiteralPath $bundle -Force -ErrorAction SilentlyContinue
    if (-not $ex.ok) { return @{ ok = $false; detail = ('解压失败: ' + $ex.text) } }
    return @{ ok = $true; dir = $dir }
}

function Get-RemoteNewestJournal {
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$Dir)
    $r = Invoke-RemoteShell -Target $Target -Command ('cmd /c dir /b /o-d ' + $Dir + '\journal')
    if (-not $r.ok -or -not $r.text) { return '' }
    $first = (($r.text.Trim() -split "\n")[0]).Trim()
    return ($first -replace '\.jsonl$', '')
}

function Save-RemoteJournal {
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$RunId, [Parameter(Mandatory)][string]$Alias)
    $remotePath = $Dir + '\journal\\' + $RunId + '.jsonl'
    $localName = 'remote-' + (($Alias -replace '[^A-Za-z0-9._-]', '_')) + '-journal-' + $RunId + '.jsonl'
    $localPath = Join-Path (Get-RemoteStateDir) $localName
    & scp -o BatchMode=yes ($Target + ':' + ($remotePath -replace '\\', '/')) $localPath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return '' }
    return $localPath
}

function Invoke-RemoteApplySession {
    <#
      在远端执行 apply（同一套引擎护栏）。
      要求：本地计划中的条目 origin 必须全是 remote:<target>。
      返回 @{ ok; exitCode; output; runId; journalPath; dir }
    #>
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string[]]$Ids,
        [int]$TimeoutSec = 600,
        [string]$RepoRoot = '',
        [switch]$Keep
    )
    if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
    $profile = Get-RemoteTargetProfile -Target $Target
    if (-not $profile.valid) { return @{ ok = $false; exitCode = 8; output = $profile.error } }
    if (-not (Test-Path -LiteralPath $PlanPath)) { return @{ ok = $false; exitCode = 2; output = ('找不到计划文件: ' + $PlanPath) } }
    $plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $origin = [string]$plan.origin
    if ($origin -ne ('remote:' + $profile.alias)) {
        return @{ ok = $false; exitCode = 2; output = ('计划的 origin=' + $origin + ' 与目标 remote:' + $profile.alias + ' 不一致，拒绝执行') }
    }
    $reach = Test-RemoteReachable -Target $profile.alias
    if (-not $reach.ok) { return @{ ok = $false; exitCode = 8; output = ('不可达: ' + $reach.text) } }
    $stage = New-RemoteStage -Target $profile.alias -RepoRoot $RepoRoot
    if (-not $stage.ok) { return @{ ok = $false; exitCode = 8; output = $stage.detail } }
    $dir = $stage.dir
    try {
        $remotePlan = $dir + '\plan.json'
        & scp -o BatchMode=yes $PlanPath ($profile.alias + ':' + ($remotePlan -replace '\\', '/')) 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return @{ ok = $false; exitCode = 8; output = '上传计划失败' } }
        $idText = ($Ids -join ',')
        $st = New-RemoteStateDir -Target $profile.alias
        if (-not $st.ok) { return @{ ok = $false; exitCode = 8; output = $st.detail } }
        $stateDir = $st.dir
        $engineArgs = 'apply --plan ' + $remotePlan + ' --ids ' + $idText + ' --yes --allow-remote-origin ' + $origin
        $run = Invoke-RemoteEngineScript -Target $profile.alias -BundleDir $dir -StateDir $stateDir -EngineArgs $engineArgs -TimeoutSec $TimeoutSec
        $runId = (Get-RemoteNewestJournal -Target $profile.alias -Dir $stateDir)
        $journalLocal = ''
        if ($runId) { $journalLocal = Save-RemoteJournal -Target $profile.alias -Dir $stateDir -RunId $runId -Alias $profile.alias }
        return @{ ok = $run.ok; exitCode = $run.exit; output = $run.text; runId = $runId; journalPath = $journalLocal; dir = $dir }
    } finally {
        if (-not $Keep) { $null = Invoke-RemoteShell -Target $profile.alias -Command ('powershell -NoProfile -Command Remove-Item -LiteralPath ' + (Format-RemotePathArg $dir) + ' -Recurse -Force -ErrorAction SilentlyContinue') -TimeoutSec 60 }
    }
}

function Invoke-RemoteRestoreSession {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Journal,
        [int]$TimeoutSec = 600,
        [string]$RepoRoot = ''
    )
    if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
    $profile = Get-RemoteTargetProfile -Target $Target
    if (-not $profile.valid) { return @{ ok = $false; exitCode = 8; output = $profile.error } }
    $reach = Test-RemoteReachable -Target $profile.alias
    if (-not $reach.ok) { return @{ ok = $false; exitCode = 8; output = ('不可达: ' + $reach.text) } }
    $stage = New-RemoteStage -Target $profile.alias -RepoRoot $RepoRoot
    if (-not $stage.ok) { return @{ ok = $false; exitCode = 8; output = $stage.detail } }
    $dir = $stage.dir
    try {
        $st = New-RemoteStateDir -Target $profile.alias
        if (-not $st.ok) { return @{ ok = $false; exitCode = 8; output = $st.detail } }
        $stateDir = $st.dir
        $run = Invoke-RemoteEngineScript -Target $profile.alias -BundleDir $dir -StateDir $stateDir -EngineArgs ('restore --journal ' + $Journal) -TimeoutSec $TimeoutSec
        $journalLocal = Save-RemoteJournal -Target $profile.alias -Dir $stateDir -RunId $Journal -Alias $profile.alias
        return @{ ok = $run.ok; exitCode = $run.exit; output = $run.text; journalPath = $journalLocal; dir = $dir }
    } finally {
        $null = Invoke-RemoteShell -Target $profile.alias -Command ('powershell -NoProfile -Command Remove-Item -LiteralPath ' + (Format-RemotePathArg $dir) + ' -Recurse -Force -ErrorAction SilentlyContinue') -TimeoutSec 60
    }
}

function New-RemoteStateDir {
    <#  远端持久状态目录（隔离区/审计日志放这里，绝不随暂存目录清理）。  #>
    param([Parameter(Mandatory)][string]$Target)
    $stateDir = 'C:\ProgramData\winmedic-remote-state'
    $mk = Invoke-RemoteShell -Target $Target -Command ('powershell -NoProfile -Command New-Item -ItemType Directory -Force -Path ' + (Format-RemotePathArg $stateDir))
    if (-not $mk.ok) { return @{ ok = $false; detail = ('无法创建远端状态目录: ' + $mk.text) } }
    return @{ ok = $true; dir = $stateDir }
}

function Invoke-RemoteEngineScript {
    <#
      在远端用指定 CDRIVE_HOME 跑一条引擎命令：写包装脚本 -> scp -> -File 执行。
      避免 cmd 引号语义问题。
    #>
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$BundleDir,
        [Parameter(Mandatory)][string]$StateDir,
        [Parameter(Mandatory)][string]$EngineArgs,
        [int]$TimeoutSec = 600
    )
    $lines = @(
        '$ErrorActionPreference = ''Continue''',
        '[Console]::OutputEncoding = [Text.Encoding]::UTF8',
        ('$env:CDRIVE_HOME = ''' + $StateDir + ''''),
        ('& ''' + $BundleDir + '\engine\winmedic.ps1'' ' + $EngineArgs),
        'exit $LASTEXITCODE'
    )
    $local = Join-Path ([IO.Path]::GetTempPath()) ('wmwrap-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.ps1')
    Set-Content -LiteralPath $local -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
    $remotePath = $BundleDir + '\run.ps1'
    & scp -o BatchMode=yes $local ($Target + ':' + ($remotePath -replace '\\', '/')) 2>&1 | Out-Null
    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { return @{ ok = $false; exit = 8; text = '上传包装脚本失败' } }
    return (Invoke-RemoteShell -Target $Target -Command ('powershell -NoProfile -ExecutionPolicy Bypass -File ' + $remotePath) -TimeoutSec $TimeoutSec)
}
