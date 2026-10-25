#Requires -Version 5.1
<#
.SYNOPSIS
  WinMedic 引擎入口。
.DESCRIPTION
  子命令：doctor | probe | plan | apply | verify | restore | journal | version | help
  退出码：0 成功 / 2 用法 / 3 权限 / 4 前置未过 / 5 plan 失效 / 6 红线 / 7 部分失败
.EXAMPLE
  .\winmedic.ps1 doctor
.EXAMPLE
  .\winmedic.ps1 probe --set storage
.EXAMPLE
  .\winmedic.ps1 apply --plan .\state\plan.json --ids R1,R2 --yes
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('doctor', 'probe', 'plan', 'apply', 'verify', 'restore', 'journal', 'profile', 'report', 'explain', 'summary', 'diff', 'relocate', 'remote', 'trend', 'diagnose', 'tools', 'selftest', 'remote-apply', 'remote-restore', 'version', 'help')]
    [string]$Command = 'help',
    [string]$SubCommand,
    [string]$Set = '',
    [string]$From,
    [string]$PlanPath,
    [string[]]$Ids,
    [string]$Journal,
    [string]$Item,
    [string]$Out,
    [string]$RunId,
    [switch]$Yes,
    [switch]$Purge,
    [string]$Exclude,
    [string]$Action,
    [string]$To,
    [switch]$AcceptRisk,
    [switch]$AcceptIrreversible,
    [string]$ConfirmToken,
    [string]$AllowRemoteOrigin,
    [string]$Origin,
    [switch]$Rebuild,
    [string]$Target,
    [string]$Via,
    [int]$TimeoutSec = 300,
    [switch]$Keep,
    [switch]$Record,
    [int]$Days = 14,
    [int]$Top = 10,
    [string]$Case,
    [switch]$List,
    [switch]$Check,
    [switch]$Remove,
    [switch]$Json,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$script:WinMedicRoot = Split-Path -Parent $PSScriptRoot
if (-not $script:WinMedicRoot) { $script:WinMedicRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Safety.ps1')
. (Join-Path $PSScriptRoot 'lib\Profile.ps1')
. (Join-Path $PSScriptRoot 'lib\Journal.ps1')
. (Join-Path $PSScriptRoot 'lib\Plan.ps1')
. (Join-Path $PSScriptRoot 'lib\Verify.ps1')
. (Join-Path $PSScriptRoot 'lib\Action.ps1')
. (Join-Path $PSScriptRoot 'lib\Report.ps1')
. (Join-Path $PSScriptRoot 'lib\Summary.ps1')
. (Join-Path $PSScriptRoot 'lib\Recommendations.ps1')
. (Join-Path $PSScriptRoot 'lib\Relocation.ps1')
. (Join-Path $PSScriptRoot 'lib\Explain.ps1')
. (Join-Path $PSScriptRoot 'lib\Remote.ps1')
. (Join-Path $PSScriptRoot 'lib\Trend.ps1')
. (Join-Path $PSScriptRoot 'lib\Diagnose.ps1')
. (Join-Path $PSScriptRoot 'lib\Tools.ps1')
. (Join-Path $PSScriptRoot 'lib\SelfTest.ps1')
. (Join-Path $PSScriptRoot 'lib\Scan.ps1')
. (Join-Path $PSScriptRoot 'probes\storage.ps1')
. (Join-Path $PSScriptRoot 'probes\boot.ps1')
. (Join-Path $PSScriptRoot 'probes\apps.ps1')
. (Join-Path $PSScriptRoot 'probes\updates.ps1')
. (Join-Path $PSScriptRoot 'probes\network.ps1')
. (Join-Path $PSScriptRoot 'probes\security.ps1')
. (Join-Path $PSScriptRoot 'probes\recovery.ps1')
. (Join-Path $PSScriptRoot 'probes\printers.ps1')
. (Join-Path $PSScriptRoot 'probes\backup.ps1')
. (Join-Path $PSScriptRoot 'probes\mail.ps1')
. (Join-Path $PSScriptRoot 'probes\workloads.ps1')

# 兼容 --set / --ids 这类双横线写法（-File 模式本就支持，直接调用时需要手动归一）
function Resolve-RestArguments {
    param([string[]]$Tokens)
    if (-not $Tokens -or $Tokens.Count -eq 0) { return }
    $i = 0
    while ($i -lt $Tokens.Count) {
        $tok = [string]$Tokens[$i]
        if ($tok.StartsWith('--')) {
            $key = $tok.Substring(2).ToLowerInvariant()
            # 布尔开关不消费后续 token
            if (@('yes', 'purge', 'json', 'remove', 'accept-risk', 'acceptrisk', 'accept-irreversible', 'acceptirreversible', 'keep', 'record', 'list', 'check') -contains $key) {
                switch ($key) {
                    'yes'                { $script:YesFlag = $true }
                    'purge'              { $script:PurgeFlag = $true }
                    'json'               { $script:JsonFlag = $true }
                    'remove'             { $script:RemoveFlag = $true }
                    'accept-risk'        { $script:AcceptRiskFlag = $true }
                    'acceptrisk'         { $script:AcceptRiskFlag = $true }
                    'accept-irreversible' { $script:AcceptIrrevFlag = $true }
                    'acceptirreversible' { $script:AcceptIrrevFlag = $true }
                    'keep'               { $script:KeepFlag = $true }
                    'record'             { $script:RecordFlag = $true }
                    'list'               { $script:ListFlag = $true }
                    'check'              { $script:CheckFlag = $true }
                }
                $i++
                continue
            }
            $val = $null
            if (($i + 1) -lt $Tokens.Count) {
                $next = [string]$Tokens[$i + 1]
                if (-not $next.StartsWith('--')) { $val = $next; $i++ }
            }
            switch ($key) {
                'set'     { if ($val) { $script:SetArg = $val } }
                'from'    { $script:FromArg = $val }
                'allow-remote-origin' { $script:AllowRemoteOriginArg = $val }
                'origin'  { $script:OriginArg = $val }
                'rebuild' { $script:RebuildArg = $true }
                'to'      { $script:ToArg = $val }
                'plan'    { $script:PlanArg = $val }
                'ids'     { if ($val) { $script:IdsArg = @($val -split ',') } }
                'journal' { $script:JournalArg = $val }
                'out'     { $script:OutArg = $val }
                'action'  { $script:ActionArg = $val }
                'exclude' { $script:ExcludeArg = $val }
                'sub'     { $script:SubArg = $val }
                'confirm-token' { if ($val) { $script:ConfirmTokenValue = $val } }
                'target'  { if ($val) { $script:TargetValue = $val } }
                'via'     { if ($val) { $script:ViaValue = $val } }
                'timeout' { if ($val) { $script:TimeoutValue = [int]$val } }
                'days'    { if ($val) { $script:DaysValue = [int]$val } }
                'top'     { if ($val) { $script:TopValue = [int]$val } }
                'case'    { if ($val) { $script:CaseValue = $val } }
                default   { Write-Log ('未知参数: ' + $tok) -Level ERROR; exit $script:EXIT.USAGE }
            }
        } elseif ($tok -match '^-(yes|purge|json|remove|accept-risk)$') {
            switch ($Matches[1].ToLowerInvariant()) {
                'yes'         { $script:YesFlag = $true }
                'purge'       { $script:PurgeFlag = $true }
                'json'        { $script:JsonFlag = $true }
                'remove'      { $script:RemoveFlag = $true }
                'accept-risk' { $script:AcceptRiskFlag = $true }
            }
        } else {
            if (-not $script:SubArg) { $script:SubArg = $tok }
        }
        $i++
    }
}

$script:SetArg = $Set
$script:FromArg = $From
$script:AllowRemoteOriginArg = [string]$AllowRemoteOrigin
$script:OriginArg = [string]$Origin
$script:ToArg = $To
$script:PlanArg = $PlanPath
$script:IdsArg = $Ids
$script:JournalArg = $Journal
$script:OutArg = $Out
$script:ActionArg = $Action
$script:ExcludeArg = $Exclude
$script:SubArg = $SubCommand
$script:YesFlag = [bool]$Yes
$script:PurgeFlag = [bool]$Purge
$script:JsonFlag = [bool]$Json
$script:RemoveFlag = [bool]$Remove
$script:AcceptRiskFlag = [bool]$AcceptRisk
$script:AcceptIrrevFlag = [bool]$AcceptIrreversible
$script:ConfirmTokenValue = [string]$ConfirmToken
$script:TargetValue = [string]$Target
$script:ViaValue = [string]$Via
$script:TimeoutValue = [int]$TimeoutSec
$script:KeepFlag = [bool]$Keep
$script:RecordFlag = [bool]$Record
$script:DaysValue = [int]$Days
$script:TopValue = [int]$Top
$script:CaseValue = [string]$Case
$script:ListFlag = [bool]$List
$script:CheckFlag = [bool]$Check
Resolve-RestArguments -Tokens $Rest
$Set = $script:SetArg
$From = $script:FromArg
$AllowRemoteOrigin = $script:AllowRemoteOriginArg
$Origin = $script:OriginArg
$Rebuild = [bool]$script:RebuildArg
$To = $script:ToArg
$PlanPath = $script:PlanArg
$Ids = $script:IdsArg
$Journal = $script:JournalArg
$Out = $script:OutArg
$Action = $script:ActionArg
$Exclude = $script:ExcludeArg
$SubCommand = $script:SubArg
$Yes = $script:YesFlag
$Purge = $script:PurgeFlag
$Json = $script:JsonFlag
$Remove = $script:RemoveFlag
$AcceptRisk = $script:AcceptRiskFlag
$AcceptIrreversible = $script:AcceptIrrevFlag
$ConfirmToken = $script:ConfirmTokenValue
$Target = $script:TargetValue
$Via = $script:ViaValue
$TimeoutSec = $script:TimeoutValue
$Keep = $script:KeepFlag
$Record = $script:RecordFlag
$Days = $script:DaysValue
$Top = $script:TopValue
$Case = $script:CaseValue
$List = $script:ListFlag
$Check = $script:CheckFlag

function Get-StatePath {
    param([string]$Name)
    $dir = Join-Path (Get-CdriveStateDir) 'state'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ($Name) { return (Join-Path $dir $Name) }
    return $dir
}

function Invoke-Doctor {
    $hostInfo = Get-HostProbe
    $d = $hostInfo.data
    if ($Json) { Write-JsonResult -Object $hostInfo | Out-Null; return $script:EXIT.OK }
    Write-Log 'WinMedic 环境自检' -Level INFO
    Write-Host ('  主机      : ' + $d.computerName)
    Write-Host ('  系统      : ' + $d.osCaption + ' (' + $d.osBuild + ')')
    Write-Host ('  型号      : ' + ($d.manufacturer + ' ' + $d.model).Trim())
    Write-Host ('  PowerShell: ' + $d.psVersion)
    Write-Host ('  管理员    : ' + $d.isAdmin)
    Write-Host ('  WizTree   : ' + $(if ($d.wiztreeFound) { $d.wiztree } else { '未找到（将降级为定向测量）' }))
    $sp = Get-DriveSpaceProbe
    if ($sp.ok) {
        Write-Host ('  C: 容量   : ' + [math]::Round($sp.data.total / 1GB, 2) + ' GB，可用 ' + [math]::Round($sp.data.free / 1GB, 2) + ' GB（已用 ' + $sp.data.usedPercent + '%）')
    }
    Write-Log '自检完成' -Level OK
    return $script:EXIT.OK
}

function Invoke-Probe {
    $set = if ($Set) { $Set.ToLower() } else { 'storage' }
    $probes = @()
    $probes += (Get-HostProbe)

    if ($set -eq 'storage' -or $set -eq 'all') {
        $probes += @(
            (Get-DriveSpaceProbe), (Get-SystemFilesProbe), (Get-RecycleBinProbe),
            (Get-UpdateLeftoversProbe), (Get-PackageCacheProbe), (Get-BrowserCacheProbe),
            (Get-OfficeCacheProbe), (Get-AppCachesProbe), (Get-CleanupTargetsProbe)
        )
        if ($set -eq 'all') { $probes += (Get-WinSxSProbe) }
    }

    if ($set -eq 'boot' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-BootTimeProbe), (Get-StartupItemsProbe), (Get-PerfBaselineProbe), (Get-DiskHealthProbe), (Get-ServicesAutoProbe))
    }

    if ($set -eq 'apps' -or $set -eq 'all') {
        $budget = if ($set -eq 'all') { 45 } else { 90 }
        $probes += @((Get-InstalledAppsProbe), (Get-AppResidueProbe -TimeBudgetSeconds $budget))
    }

    if ($set -eq 'updates' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-WindowsUpdateProbe), (Get-DriverProbe))
    }

    if ($set -eq 'network' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-NetworkAdaptersProbe), (Get-DnsConfigProbe), (Get-ProxyConfigProbe), (Get-VpnAdaptersProbe))
    }

    if ($set -eq 'security' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-SecurityPostureProbe))
    }

    if ($set -eq 'recovery' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-RecoveryReadinessProbe))
    }

    if ($set -eq 'printers' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-PrintersProbe))
    }

    if ($set -eq 'backup' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-BackupStatusProbe))
    }

    if ($set -eq 'mail' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-MailClientsProbe))
    }

    if ($set -eq 'workloads' -or $set -eq 'all' -or $set -eq 'intake') {
        $probes += @((Get-WorkloadsProbe -TimeBudgetSeconds 60), (Get-ProxyChainProbe))
    }

    if ($set -eq 'relocation') {
        $probes += @((Get-RelocationProbe -TimeBudgetSeconds 60))
    }

    if ($set -eq 'intake') {
        # intake 是「首次全面体检」，必须覆盖 storage 组，否则 C 盘诊断凑不齐证据
        $probes += @(
            (Get-DriveSpaceProbe), (Get-SystemFilesProbe), (Get-RecycleBinProbe),
            (Get-UpdateLeftoversProbe), (Get-PackageCacheProbe), (Get-BrowserCacheProbe),
            (Get-OfficeCacheProbe), (Get-AppCachesProbe)
        )
    }

    if ($probes.Count -le 1) {
        Write-Log ('未知探针集: ' + $Set + '（可用 storage / boot / apps / updates / network / security / recovery / printers / backup / mail / workloads / relocation / intake / all）') -Level ERROR
        return $script:EXIT.USAGE
    }

    $candidates = @()
    foreach ($p in $probes) { if ($p.candidates) { $candidates += $p.candidates } }
    $hostProbe = $probes | Where-Object { $_.id -eq 'probe.host' } | Select-Object -First 1
    $hostData = $hostProbe.data

    $findings = [ordered]@{
        schemaVersion = 1
        generatedAt   = (Get-IsoTimestamp)
        probeSet      = $Set
        host          = $hostData
        probes        = @($probes | ForEach-Object { @{ id = $_.id; ok = $_.ok; data = $_.data } })
        candidates    = @($candidates)
    }

    $outPath = if ($Out) { $Out } else { Get-StatePath ($Set + '-findings.json') }
    Write-JsonResult -Object $findings -Path $outPath | Out-Null

    if ($Json) { Write-JsonResult -Object $findings | Out-Null; return $script:EXIT.OK }
    Write-Log ('探针集 [' + $Set + '] 完成，共 ' + $probes.Count + ' 个探针，候选 ' + $candidates.Count + ' 项') -Level OK
    Write-Host ('  结果: ' + $outPath)
    $failed = @($probes | Where-Object { -not $_.ok })
    foreach ($f in $failed) { Write-Host ('  [!] 未取得: ' + $f.id) }
    if ($candidates.Count -gt 0) {
        $sum = 0L
        foreach ($c in $candidates) { $sum += [int64]$c.size }
        Write-Host ('  候选合计: ' + [math]::Round($sum / 1GB, 2) + ' GB')
    }
    return $script:EXIT.OK
}

function Invoke-Plan {
    $src = if ($From) { $From } else { Resolve-FindingsPath }
    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        Write-Log ('找不到 findings：' + $src + '（先运行 probe）') -Level ERROR
        return $script:EXIT.USAGE
    }
    $findings = Get-Content -LiteralPath $src -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $findings.candidates) {
        Write-Log '候选为空，没有可执行项' -Level WARN
    }
    $plan = New-CdrivePlan -Findings $findings
    $planPath = if ($PlanPath) { $PlanPath } else { Get-StatePath 'plan.json' }
    $mdPath = [IO.Path]::ChangeExtension($planPath, '.md')
    Write-JsonResult -Object $plan -Path $planPath | Out-Null
    $md = Format-PlanMarkdown -Plan $plan
    [IO.File]::WriteAllText($mdPath, $md, (New-Object Text.UTF8Encoding($false)))

    if ($Json) { Write-JsonResult -Object $plan | Out-Null; return $script:EXIT.OK }
    Write-Host $md
    Write-Host ''
    Write-Log ('方案已写入: ' + $planPath) -Level OK
    return $script:EXIT.OK
}

function Invoke-Apply {
    # standalone 动作（仅 Tier 1 且 catalog 显式标注）：不依赖 plan，必须先于 plan 校验
    if ($Action) {
        if (-not $Yes) { Write-Log 'apply 需要显式 --yes 才执行' -Level ERROR; return $script:EXIT.USAGE }
        $sCat = Import-CdriveCatalog
        $sAct = $sCat.Actions[$Action]
        if (-not $sAct) { Write-Log ('未知动作: ' + $Action) -Level ERROR; return $script:EXIT.USAGE }
        if (-not $sAct.standalone) { Write-Log ('该动作不是 standalone，必须通过 plan 执行: ' + $Action) -Level ERROR; return $script:EXIT.USAGE }
        if ([int]$sAct.tier -ge 2) { Write-Log ('standalone 动作必须为 Tier 1: ' + $Action) -Level ERROR; return $script:EXIT.USAGE }
        if (-not (Test-IsAdmin)) { Write-Log '需要管理员权限' -Level ERROR; return $script:EXIT.NO_ADMIN }
        $ridS = if ($RunId) { $RunId } else { New-RunId }
        Write-Log ('执行 standalone 动作 ' + $sAct.id + '，runId=' + $ridS)
        $pseudo = [pscustomobject]@{ id = 'S1'; target = '(standalone)'; actionId = $sAct.id }
        Write-JournalRecord -RunId $ridS -Record @{ itemId = 'S1'; actionId = $sAct.id; target = '(standalone)'; kind = $sAct.kind; phase = 'begin' }
        $rrS = Invoke-CdriveAction -Item $pseudo -Action $sAct -RunId $ridS
        $vvS = Invoke-ActionVerify -Action $sAct -Item $pseudo
        Write-JournalRecord -RunId $ridS -Record @{ itemId = 'S1'; actionId = $sAct.id; target = '(standalone)'; kind = $sAct.kind; mode = $rrS.mode; ok = $rrS.ok; error = $rrS.error; outputSha256 = $rrS.outputSha256; verifyAllOk = $vvS.allOk; pendingReboot = $vvS.pendingReboot; phase = 'done' }
        if ($rrS.ok) { Write-Log ('完成: ' + $sAct.id) -Level OK } else { Write-Log ('失败: ' + $rrS.error) -Level ERROR }
        Write-Host ('  回滚: 该动作不可自动回滚，效果见 verify；runId=' + $ridS)
        if ($rrS.ok) { return $script:EXIT.OK } else { return $script:EXIT.PARTIAL }
    }

    $p = if ($PlanPath) { $PlanPath } else { Get-StatePath 'plan.json' }
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Log ('找不到 plan：' + $p) -Level ERROR
        return $script:EXIT.USAGE
    }
    # 远端来源的计划绝不能本地执行（在权限检查前就拦住，保证语义与权限无关）
    if (Test-Path -LiteralPath $p) {
        try {
            $prePlan = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            $originCheck = Test-PlanOriginAllowed -Plan $prePlan -AllowRemoteOrigin ([string]$AllowRemoteOrigin)
            if (-not $originCheck.allowed) {
                Write-Log ('计划里有来自远端的项（' + ($originCheck.offending -join ',') + '），本地 apply 拒绝执行') -Level ERROR
                Write-Log '请改用: winmedic.ps1 remote-apply --target <别名> --plan <本计划文件> --ids <ids> --yes' -Level INFO
                return $script:EXIT.USAGE
            }
        } catch { }
    }

    if (-not $Yes) {
        Write-Log 'apply 需要显式 --yes 才执行' -Level ERROR
        return $script:EXIT.USAGE
    }
    if (-not $Ids -or $Ids.Count -eq 0) {
        Write-Log '未指定 --ids，拒绝执行（避免误清空）' -Level ERROR
        return $script:EXIT.USAGE
    }

    if (-not (Test-IsAdmin)) {
        Write-Log '需要管理员权限' -Level ERROR
        return $script:EXIT.NO_ADMIN
    }
    $plan = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $integrity = Test-PlanIntegrity -Plan $plan
    if (-not $integrity.Ok) {
        Write-Log ('plan 校验失败：期望 ' + $integrity.Expected + '，实际 ' + $integrity.Actual) -Level ERROR
        return $script:EXIT.PLAN_INVALID
    }
    $cat = Import-CdriveCatalog
    $targetItems = @()
    if ($Ids -and $Ids.Count -gt 0) {
        foreach ($id in $Ids) {
            $found = $plan.items | Where-Object { $_.id -eq $id } | Select-Object -First 1
            if (-not $found) { Write-Log ('plan 中不存在 id: ' + $id) -Level ERROR; return $script:EXIT.USAGE }
            $targetItems += $found
        }
    } else {
        Write-Log '未指定 --ids，拒绝执行（避免误清空）' -Level ERROR
        return $script:EXIT.USAGE
    }


    # 风险门：恢复能力不足时拦截 Tier 3+
    $recoveryLevel = 'unknown'
    $fpNow = Resolve-FindingsPath
    if ($fpNow) {
        try {
            $fNow = Get-Content -LiteralPath $fpNow -Raw -Encoding UTF8 | ConvertFrom-Json
            $rpNow = @($fNow.probes | Where-Object { $_.id -eq 'probe.recovery-readiness' }) | Select-Object -First 1
            if ($rpNow -and $rpNow.data) { $recoveryLevel = [string]$rpNow.data.level }
        } catch { }
    }
    $gate = Test-RiskGate -Items $targetItems -RecoveryLevel $recoveryLevel -AcceptRisk:$AcceptRisk
    if (-not $gate.allow) {
        Write-Log ('风险门拒绝: ' + $gate.reason) -Level ERROR
        return $script:EXIT.PRECONDITION
    }
    if ($gate.reason -ne '无可回滚风险项') { Write-Log ('风险门: ' + $gate.reason) -Level WARN }

    
    $purgeGate = Test-PurgeAllowed -Purge:$Purge -AcceptIrreversible:$AcceptIrreversible
    if (-not $purgeGate.allow) {
        Write-Log ('不可逆操作被拒绝: ' + $purgeGate.reason) -Level ERROR
        return $script:EXIT.USAGE
    }
    if ($Purge) { Write-Log '已进入 purge 模式：删除不可回滚' -Level WARN }

    if ($Purge) {
        $sheetItems = @()
        foreach ($t in $targetItems) {
            $tAct = $cat.Actions[$t.actionId]
            $sz = 0L
            if ($t.PSObject.Properties.Name -contains 'sizeBytes') { $sz = [int64]$t.sizeBytes }
            $sheetItems += [pscustomobject]@{ id = $t.id; actionId = $t.actionId; target = $t.target; sizeBytes = $sz; action = $tAct }
        }
        $token = New-PurgeConfirmationToken -PlanHash ([string]$integrity.Actual) -Ids @($targetItems | ForEach-Object { [string]$_.id })
        Write-Host (Format-PurgeConfirmation -Items $sheetItems -PlanHash ([string]$integrity.Actual) -Token $token)
        Write-Host ''
        $given = ''
        if ($ConfirmToken) { $given = $ConfirmToken.Trim().ToUpperInvariant() }
        if ($given -ne $token) {
            if ($given) { Write-Log ('确认令牌不匹配（收到 ' + $given + '，应为 ' + $token + '）') -Level ERROR }
            else { Write-Log '未回填 --confirm-token，已中止；没有删除任何东西' -Level ERROR }
            Write-Log '请把上面的确认单完整展示给用户，得到同意后再用单子末尾的令牌重跑。' -Level INFO
            return $script:EXIT.USAGE
        }
        Write-Log '确认令牌校验通过，开始物理删除' -Level WARN
    }

    $runId = if ($RunId) { $RunId } else { New-RunId }
    Write-Log ('开始执行，runId=' + $runId + '，共 ' + $targetItems.Count + ' 项')
    $fail = 0
    foreach ($it in $targetItems) {
        $act = $cat.Actions[$it.actionId]
        if (-not $act) { Write-Log ('缺少动作定义: ' + $it.actionId) -Level ERROR; $fail++; continue }
        if ([int]$act.tier -ge 4) { Write-Log ('Tier 4 拒绝: ' + $it.actionId) -Level ERROR; $fail++; continue }
        $profNow = Get-CdriveProfile
        if (Test-ExcludedPath -Target $it.target -Patterns @($profNow.exclude)) {
            Write-Log ('用户保留项拒绝: ' + $it.target) -Level WARN
            Write-JournalRecord -RunId $runId -Record @{ itemId = $it.id; actionId = $it.actionId; target = $it.target; result = 'skipped'; reason = 'user-exclude' }
            continue
        }
        if (Test-StateDirPath -Path $it.target) {
            Write-Log ('拒绝清理引擎自身目录: ' + $it.target) -Level ERROR
            $fail++; continue
        }
        if (Test-RedlinePath -Path $it.target) {
            Write-Log ('红线拒绝: ' + $it.target + ' (' + (Get-RedlineReason -Path $it.target) + ')') -Level ERROR
            $fail++; continue
        }
        $pre = Invoke-PreconditionList -Specs $act.requires
        $preFail = $pre | Where-Object { -not $_.Ok }
        if ($preFail) {
            Write-Log ('前置未通过 [' + $it.id + ']: ' + ($preFail | ForEach-Object { $_.Detail }) -join '; ') -Level WARN
            Write-JournalRecord -RunId $runId -Record @{ itemId = $it.id; actionId = $it.actionId; target = $it.target; result = 'skipped'; reason = 'precondition'; detail = ($preFail | ForEach-Object { $_.Detail }) -join '; ' }
            continue
        }
        Write-Log ('执行 ' + $it.id + ' ' + $it.actionId + ' -> ' + $it.target)
        Write-JournalRecord -RunId $runId -Record @{ itemId = $it.id; actionId = $it.actionId; target = $it.target; kind = $act.kind; phase = 'begin' }
        $r = Invoke-CdriveAction -Item $it -Action $act -RunId $runId -Purge:$Purge
        $ver = Invoke-ActionVerify -Action $act -Item $it
        $recResult = if ($r.alreadyAbsent) { 'skipped' } else { 'ok' }
        $rec = @{
            itemId = $it.id; actionId = $it.actionId; target = $it.target; kind = $act.kind
            mode = $r.mode; ok = $r.ok; error = $r.error; quarantinePath = $r.quarantinePath
            exitCode = $r.exitCode; outputSha256 = $r.outputSha256
            freeBefore = $r.freeBefore; freeAfter = $r.freeAfter
            verifyAllOk = $ver.allOk; pendingReboot = $ver.pendingReboot; verify = $ver.results
            phase = 'done'
        }
        Write-JournalRecord -RunId $runId -Record $rec
        if ($r.alreadyAbsent) { Write-Log ($it.id + ' 目标已不存在，跳过') -Level WARN }
        elseif ($r.ok) { Write-Log ($it.id + ' 完成') -Level OK } else { Write-Log ($it.id + ' 失败: ' + $r.error) -Level ERROR; $fail++ }
    }

    Write-Host ''
    Write-Log ('执行结束，runId=' + $runId) -Level OK
    Write-Host ('  回滚: .\winmedic.ps1 restore --journal ' + $runId)
    if ($fail -gt 0) { return $script:EXIT.PARTIAL }
    return $script:EXIT.OK
}

function Invoke-VerifyCmd {
    if (-not $Journal) { Write-Log 'verify 需要 --journal <runId>' -Level ERROR; return $script:EXIT.USAGE }
    $recs = Get-JournalRecords -RunId $Journal
    if ($recs.Count -eq 0) { Write-Log '该 runId 没有记录' -Level WARN; return $script:EXIT.USAGE }
    $doneRecs = @($recs | Where-Object { -not ($_.PSObject.Properties.Name -contains 'phase') -or [string]$_.phase -eq 'done' })
    $out = @()
    foreach ($r in $doneRecs) {
        $out += [pscustomobject]@{
            itemId = $r.itemId; actionId = $r.actionId; ok = $r.ok; mode = $r.mode
            pendingReboot = $r.pendingReboot; verifyAllOk = $r.verifyAllOk
            freeDelta = if ($null -ne $r.freeBefore -and $null -ne $r.freeAfter) { [int64]($r.freeAfter - $r.freeBefore) } else { 0 }
        }
    }
    if ($Json) { Write-JsonResult -Object $out | Out-Null; return $script:EXIT.OK }
    Write-Log ('runId=' + $Journal + ' 验证结果')
    foreach ($o in $out) {
        $delta = [math]::Round($o.freeDelta / 1GB, 3)
        Write-Host ('  ' + $o.itemId + '  ' + $o.actionId + '  ok=' + $o.ok + '  可用空间变化 ' + $delta + ' GB' + $(if ($o.pendingReboot) { '  [需重启生效]' } else { '' }))
    }
    $orphans = @(Get-JournalOrphans -RunId $Journal)
    if ($orphans.Count -gt 0) {
        Write-Host ''
        Write-Log ('发现 ' + $orphans.Count + ' 个中断残留（有 begin 无 done）') -Level WARN
        foreach ($o in $orphans) {
            $hint = if ($o.hasQuarantine) { '隔离区有文件，可 restore 救回' } else { '隔离区为空，可能未实际移动' }
            Write-Host ('  ' + $o.itemId + ' ' + $o.actionId + ' -> ' + $o.target + '  [' + $hint + ']')
        }
    }
    $sp = Get-DriveSpaceProbe
    if ($sp.ok) { Write-Host ('  C: 当前可用 ' + [math]::Round($sp.data.free / 1GB, 2) + ' GB') }
    return $script:EXIT.OK
}

function Invoke-Restore {
    if (-not $Journal) { Write-Log 'restore 需要 --journal <runId>' -Level ERROR; return $script:EXIT.USAGE }
    if (-not (Test-IsAdmin)) { Write-Log '需要管理员权限' -Level ERROR; return $script:EXIT.NO_ADMIN }
    $recs = Get-JournalRecords -RunId $Journal
    if ($recs.Count -eq 0) { Write-Log '该 runId 没有记录' -Level WARN; return $script:EXIT.USAGE }
    $restored = 0; $failed = 0
    foreach ($r in $recs) {
        if ($Item -and $r.itemId -ne $Item) { continue }
        if ($r.mode -ne 'quarantine') { continue }
        $res = Restore-JournalQuarantine -Record $r
        if ($res.ok) {
            Write-Log ('已恢复: ' + $res.target) -Level OK
            $restored++
            Write-JournalRecord -RunId $Journal -Record @{ itemId = $r.itemId; actionId = $r.actionId; target = $res.target; result = 'restored' }
        } else {
            Write-Log ('恢复失败: ' + $res.target + ' -> ' + $res.detail) -Level ERROR
            $failed++
        }
    }
    foreach ($o in @(Get-JournalOrphans -RunId $Journal)) {
        if ($Item -and $o.itemId -ne $Item) { continue }
        if (-not $o.hasQuarantine) { continue }
        $children = @(Get-ChildItem -LiteralPath $o.quarantinePath -Force -ErrorAction SilentlyContinue)
        if ($children.Count -ne 1) {
            Write-Log ('中断项 ' + $o.itemId + ' 的隔离目录内容不唯一，需人工确认: ' + $o.quarantinePath) -Level WARN
            $failed++
            continue
        }
        $rec = [pscustomobject]@{ itemId = $o.itemId; target = $o.target; quarantinePath = $children[0].FullName }
        $res = Restore-JournalQuarantine -Record $rec
        if ($res.ok) {
            Write-Log ('已救回中断项: ' + $res.target) -Level OK
            $restored++
            Write-JournalRecord -RunId $Journal -Record @{ itemId = $o.itemId; target = $res.target; result = 'restored-orphan' }
        } else {
            Write-Log ('救回失败: ' + $res.detail) -Level ERROR
            $failed++
        }
    }
    Write-Log ('恢复完成：成功 ' + $restored + '，失败 ' + $failed) -Level OK
    if ($failed -gt 0) { return $script:EXIT.PARTIAL }
    return $script:EXIT.OK
}

function Invoke-JournalCmd {
    if ($SubCommand -eq 'show' -and $Journal) {
        $recs = Get-JournalRecords -RunId $Journal
        if ($Json) { Write-JsonResult -Object $recs | Out-Null } else { $recs | Format-List | Out-String | Write-Host }
        return $script:EXIT.OK
    }
    $list = Get-JournalList
    if ($Json) { Write-JsonResult -Object $list | Out-Null } else { Write-Host '可用 runId:'; $list | ForEach-Object { Write-Host ('  ' + $_) } }
    return $script:EXIT.OK
}

function Invoke-Profile {
    if ($Exclude) {
        $r = Add-CdriveExclusion -Pattern $Exclude
        Write-Log ('已加入保留项: ' + $Exclude) -Level OK
        Write-Host ('  当前保留项: ' + ($r.exclude -join '; '))
        return $script:EXIT.OK
    }
    if ($Remove) {
        if (-not $Exclude) { Write-Log '移除保留项需要 --exclude <模式>' -Level ERROR; return $script:EXIT.USAGE }
        $r = Remove-CdriveExclusion -Pattern $Exclude
        Write-Log ('已移除保留项: ' + $Exclude) -Level OK
        Write-Host ('  当前保留项: ' + ($r.exclude -join '; '))
        return $script:EXIT.OK
    }
    $prof = Get-CdriveProfile
    if ($Json) { Write-JsonResult -Object $prof | Out-Null; return $script:EXIT.OK }
    Write-Log '当前 Profile' -Level INFO
    Write-Host ('  配置文件: ' + (Get-ProfilePath))
    if (@($prof.exclude).Count -eq 0) {
        Write-Host '  保留项: (无)'
    } else {
        Write-Host '  保留项:'
        foreach ($e in $prof.exclude) { Write-Host ('    ' + $e) }
    }
    Write-Host '  提示: 保留项命中的目标在 plan 阶段被排除，apply 阶段再次拦截。'
    return $script:EXIT.OK
}

function Resolve-FindingsPath {
    <#  $Set 明确指定时优先该探针集；否则取最新的一次采集。  #>
    $state = Get-StatePath
    if ($Set) {
        $specific = Join-Path $state ($Set + '-findings.json')
        if (Test-Path -LiteralPath $specific) { return $specific }
    }
    $legacy = Join-Path $state 'findings.json'
    if (-not $Set -and (Test-Path -LiteralPath $legacy)) { }
    $newest = Get-ChildItem -LiteralPath $state -Filter '*-findings.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest) { return $newest.FullName }
    if (Test-Path -LiteralPath $legacy) { return $legacy }
    return $null
}

function Invoke-Report {
    $fp = Resolve-FindingsPath
    if (-not $fp) {
        Write-Log '找不到 findings，请先运行 probe' -Level ERROR
        return $script:EXIT.USAGE
    }
    $findings = Get-Content -LiteralPath $fp -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = $null
    $pp = Get-StatePath 'plan.json'
    if (Test-Path -LiteralPath $pp) {
        try { $plan = Get-Content -LiteralPath $pp -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    $records = @()
    $rid = $Journal
    if (-not $rid) {
        $list = Get-JournalList
        if ($list.Count -gt 0) { $rid = $list[0] }
    }
    if ($rid) { $records = @(Get-JournalRecords -RunId $rid) }
    $md = Format-WinMedicReport -Findings $findings -Plan $plan -JournalRecords $records -RunId $rid
    $outPath = if ($Out) { $Out } else { Get-StatePath ('report-' + (Get-CompactTimestamp) + '.md') }
    [IO.File]::WriteAllText($outPath, $md, (New-Object Text.UTF8Encoding($false)))
    if ($Json) { Write-JsonResult -Object @{ report = $outPath; runId = $rid; findings = $fp } | Out-Null; return $script:EXIT.OK }
    Write-Host $md
    Write-Host ''
    Write-Log ('报告已写入: ' + $outPath) -Level OK
    return $script:EXIT.OK
}

function Invoke-Explain {
    $cat = Import-CdriveCatalog
    if (-not $Action) {
        Write-Host '可用动作（id / 级别 / 类型 / 可回滚 / 证据）'
        foreach ($a in ($cat.Actions.Values | Sort-Object { $_.domain }, { $_.id })) {
            Write-Host ('  {0,-42} {1}  {2,-11} {3,-8} {4}' -f $a.id, $a.tier, $a.kind, $a.reversible, $a.evidence)
        }
        Write-Host ''
        Write-Host '用 explain --action <id> 查看某条动作的完整依据。'
        return $script:EXIT.OK
    }
    $act = $cat.Actions[$Action]
    if (-not $act) { Write-Log ('未知动作: ' + $Action) -Level ERROR; return $script:EXIT.USAGE }
    Write-Host ('动作: ' + $act.id)
    Write-Host ('  域 / 级别 : ' + $act.domain + ' / Tier ' + $act.tier)
    Write-Host ('  类型      : ' + $act.kind)
    Write-Host ('  可回滚    : ' + $act.reversible)
    if ($act.rollback) { Write-Host ('  回滚方式  : ' + $act.rollback) }
    if ($act.command) { Write-Host ('  命令      : ' + $act.command) }
    Write-Host ('  前置检查  : ' + ((@($act.requires)) -join ', '))
    if (@($act.cautions).Count -gt 0) {
        Write-Host '  注意事项  :'
        foreach ($c in @($act.cautions)) { Write-Host ('    - ' + $c) }
    }
    $ev = $cat.Evidence[[string]$act.evidence]
    Write-Host '  证据      :'
    if ($ev) {
        Write-Host ('    [' + $ev.strength + '] ' + $ev.id)
        if ($ev.quote) { Write-Host ('    原文: ' + $ev.quote) }
        foreach ($l in @($ev.links)) { if ($l) { Write-Host ('    链接: ' + $l) } }
        Write-Host ('    核对于: ' + $ev.verifiedOn)
        if ($ev.notes) { Write-Host ('    备注: ' + $ev.notes) }
    } else {
        Write-Host '    (缺失，属于 catalog 缺陷)'
    }
    Write-Host '  验证规则  :'
    foreach ($v in @($act.verify)) { Write-Host ('    - ' + $v.kind) }
    return $script:EXIT.OK
}

function Invoke-Summary {
    $fp = Resolve-FindingsPath
    if (-not $fp) { Write-Log '找不到 findings，请先运行 probe' -Level ERROR; return $script:EXIT.USAGE }
    $findings = Get-Content -LiteralPath $fp -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($Json) {
        Write-JsonResult -Object @{
            host = $findings.host
            probeSet = $findings.probeSet
            generatedAt = $findings.generatedAt
            domains = @(Get-SummaryLines -Findings $findings)
            recommendations = @(Get-SummaryRecommendations -Findings $findings)
        }
        return $script:EXIT.OK
    }
    Write-Host (Format-WinMedicSummary -Findings $findings)
    Write-Host ''
    Write-Host ('  数据源: ' + $fp)
    return $script:EXIT.OK
}

function Invoke-Diff {
    if (-not $From -or -not $To) {
        Write-Log 'diff 需要 --from <基线 findings.json> --to <对比 findings.json>' -Level ERROR
        return $script:EXIT.USAGE
    }
    foreach ($f in @($From, $To)) {
        if (-not (Test-Path -LiteralPath $f)) { Write-Log ('找不到文件: ' + $f) -Level ERROR; return $script:EXIT.USAGE }
    }
    $b = Get-Content -LiteralPath $From -Raw -Encoding UTF8 | ConvertFrom-Json
    $a = Get-Content -LiteralPath $To -Raw -Encoding UTF8 | ConvertFrom-Json
    $txt = Format-FindingsDiff -Before $b -After $a
    if ($Json) {
        Write-JsonResult -Object @{ before = (Get-DiffMetrics -Findings $b); after = (Get-DiffMetrics -Findings $a) } | Out-Null
        return $script:EXIT.OK
    }
    Write-Host $txt
    return $script:EXIT.OK
}

function Invoke-Relocate {
    $volumes = Get-RelocationVolumeProfile
    $known = Get-RelocationKnownFolders
    $declared = Get-AppDeclaredPaths
    $wl = Get-WorkloadsProbe -TimeBudgetSeconds 60
    $facts = Get-RelocationFacts -Workloads @($wl.data.workloads) -Volumes $volumes -KnownFolders $known -DeclaredPaths $declared
    $checklist = Get-RelocationChecklist
    $hints = Get-RelocationAdvice -Workloads @($wl.data.workloads) -Volumes $volumes -KnownFolders $known -DeclaredPaths $declared -SystemDrive 'C:'

    if ($Json) {
        Write-JsonResult -Object @{
            volumes = $volumes
            knownFolders = $known
            declaredPaths = $declared
            checklist = $checklist
            facts = @($facts)
            defaultHints = @($hints)
            notice = 'facts 是事实，defaultHints 只是默认参考；最终方案由 Agent 结合上下文判断，并须逐条回答 checklist'
        }
        return $script:EXIT.OK
    }

    Write-Host '磁盘概况'
    foreach ($k in ($volumes.Keys | Sort-Object)) {
        $v = $volumes[$k]
        Write-Host ('  {0}  {1,-5} 共 {2} GB 可用 {3} GB' -f $k, $v.media, $v.totalGB, $v.freeGB)
    }
    Write-Host ''
    Write-Host '决策清单（必须逐条判断，并把结论写进给用户的回答里）'
    $i = 0
    foreach ($q in $checklist) { $i++; Write-Host ('  ' + $i + '. ' + $q) }
    Write-Host ''
    Write-Host '事实'
    Write-Host (Format-RelocationFacts -Facts $facts)
    Write-Host ''
    Write-Host '默认建议（仅供参考，可被判断推翻；不要当结论直接转述）'
    $act = @($hints | Where-Object { $_.action -in @('move', 'known-folder', 'known-folder-then-app') })
    if ($act.Count -eq 0) { Write-Host '  （默认视角下无待处理项）' }
    else {
        foreach ($a in $act) { Write-Host ('  [' + $a.policySource + '] ' + $a.workload + ' / ' + $a.label + ' -> ' + $a.action + ' ' + $a.target + '  ' + $a.reason) }
    }
    Write-Host ''
    Write-Host '提示：引擎不执行迁移。给出方案前请确认目标盘空间与软件是否已退出。'
    return $script:EXIT.OK
}

function Invoke-RemoteCmd {
    if (-not $Target) {
        Write-Log 'remote 需要 --target <ssh 别名或 user@host>' -Level ERROR
        Write-Log '示例: winmedic.ps1 remote --target augenstern-adm --set intake' -Level INFO
        return $script:EXIT.USAGE
    }
    $viaActual = 'ssh'
    if ($Via -and $Via.ToLower() -eq 'local') { $viaActual = 'local' }
    $setActual = if ($Set) { $Set.ToLower() } else { 'intake' }
    $res = Invoke-RemoteSession -Target $Target -Set $setActual -Via $viaActual -TimeoutSec $TimeoutSec -Keep:$Keep
    if ($Json) {
        Write-JsonResult -Object $res
        return $res.exitCode
    }
    if (-not $res.ok) {
        Write-Log ('远程采集失败: ' + $res.detail) -Level ERROR
        Write-Log '排查顺序: 1) ssh 别名能否解析 2) 目标机是否开机 3) ssh -o BatchMode=yes <target> echo ok' -Level INFO
        return $res.exitCode
    }
    Write-Log ('远程采集完成 (' + $res.seconds + 's, ' + $res.detail + ')') -Level OK
    Write-Host ('  findings: ' + $res.findingsPath)
    Write-Host ('  runId   : ' + $res.runId)
    Write-Host '  提示: 远端数据的 origin 为 remote:<别名>，本地 apply 会拒绝这些条目'
    return $script:EXIT.OK
}

function Invoke-TrendCmd {
    if ($Rebuild) {
        $stateDir = Join-Path (Get-CdriveStateDir) 'state'
        $trendPath = Get-TrendFile
        if (Test-Path -LiteralPath $trendPath) {
            $bak = $trendPath + '.bak.' + (Get-Date).ToString('yyyyMMdd-HHmmss')
            Copy-Item -LiteralPath $trendPath -Destination $bak -Force
            Write-Log ('已备份旧序列: ' + $bak) -Level OK
        }
        $files = @(Get-ChildItem -LiteralPath $stateDir -Filter '*-findings.json' -File -ErrorAction SilentlyContinue)
        if (@($files).Count -eq 0) { Write-Log '没有 findings 可重建' -Level ERROR; return $script:EXIT.PRECONDITION }
        $n = 0; $dup = 0
        foreach ($f in $files) {
            try {
                $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $origin = 'local'
                foreach ($pr in @($j.probes)) { if ($pr.PSObject.Properties.Name -contains 'origin' -and $pr.origin) { $origin = [string]$pr.origin; break } }
                $snap = Get-TrendSnapshot -Findings $j -Origin $origin
                $measured = $null
                if ($j.PSObject.Properties.Name -contains 'generatedAt' -and $j.generatedAt) { $measured = [string]$j.generatedAt }
                if (-not $measured) { $measured = $f.LastWriteTime.ToString('o') }
                $snap.ts = $measured
                if (Add-TrendRecord -Snapshot $snap) { $n++ } else { $dup++ }
            } catch { }
        }
        if ($Json) { Write-JsonResult -Object @{ rebuilt = $n; skippedDuplicate = $dup; path = $trendPath } | Out-Null }
        else { Write-Log ('重建完成：写入 ' + $n + ' 条，跳过重复 ' + $dup + ' 条') -Level OK; Write-Host ('  ' + $trendPath) }
        return $script:EXIT.OK
    }

    if ($Record) {
        $stateDir = Join-Path (Get-CdriveStateDir) 'state'
        $files = @()
        if ($Set) {
            $one = Join-Path $stateDir ($Set.ToLower() + '-findings.json')
            if (Test-Path -LiteralPath $one) { $files = @(Get-Item -LiteralPath $one) }
        } else {
            $files = @(Get-ChildItem -LiteralPath $stateDir -Filter '*-findings.json' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike 'remote-*' } |
                Group-Object { ($_.BaseName -replace '-findings$', '') } |
                ForEach-Object { $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1 })
        }
        if (@($files).Count -eq 0) {
            Write-Log '没有可用的 findings，请先 probe' -Level ERROR
            return $script:EXIT.PRECONDITION
        }
        $count = 0
        $dup = 0
        foreach ($f in @($files)) {
            $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $origin = 'local'
            foreach ($pr in @($j.probes)) { if ($pr.PSObject.Properties.Name -contains 'origin' -and $pr.origin) { $origin = [string]$pr.origin; break } }
            $snap = Get-TrendSnapshot -Findings $j -Origin $origin
            # 关键：时间戳必须是『测量时刻』，不能用记录时刻，否则旧数据会被当成新样本
            $measured = $null
            if ($j.PSObject.Properties.Name -contains 'generatedAt' -and $j.generatedAt) { $measured = [string]$j.generatedAt }
            if (-not $measured) { $measured = $f.LastWriteTime.ToString('o') }
            $snap.ts = $measured
            $added = Add-TrendRecord -Snapshot $snap
            if ($added) { $count++ } else { $dup++ }
        }
        $path = Get-TrendFile
        if ($Json) { Write-JsonResult -Object @{ recorded = $count; path = $path } | Out-Null }
        else {
            Write-Log ('已记录 ' + $count + ' 条快照' + $(if ($dup -gt 0) { '（跳过重复 ' + $dup + ' 条）' } else { '' })) -Level OK
            Write-Host ('  ' + $path)
        }
        return $script:EXIT.OK
    }

    $loaded = Get-TrendRecords
    $records = @($loaded.records)
    if ($loaded.badLines -gt 0) { Write-Log ('跳过 ' + $loaded.badLines + ' 行损坏记录') -Level WARN }
    if ($Days -gt 0) {
        $cut = (Get-Date).AddDays(-1 * $Days)
        $records = @($records | Where-Object { try { [datetime]$_.ts -ge $cut } catch { $false } })
    }
    $names = @(Get-TrendMetricNames -Records $records)
    $growth = @()
    foreach ($n in $names) {
        $series = @()
        foreach ($r in $records) {
            if (-not $r.metrics) { continue }
            if (-not ($r.metrics.PSObject.Properties.Name -contains $n)) { continue }
            $series += [pscustomobject]@{ ts = [string]$r.ts; value = [double]$r.metrics.$n }
        }
        $growth += (Get-TrendGrowth -Series $series -Metric $n)
    }
    if ($Json) { Write-JsonResult -Object @{ records = $records.Count; badLines = $loaded.badLines; growth = @($growth) } | Out-Null; return $script:EXIT.OK }
    Write-Host (Format-TrendReport -Growth $growth -Top $Top -RecordCount $records.Count)
    return $script:EXIT.OK
}

function Invoke-DiagnoseCmd {
    $catalog = @(Get-DiagnosisCatalog)
    if ($List -or -not $Case) {
        if ($Json) { Write-JsonResult -Object @{ cases = @($catalog | ForEach-Object { @{ id = $_.id; title = $_.title; hypotheses = @($_.hypotheses).Count } }) } | Out-Null; return $script:EXIT.OK }
        Write-Host (Format-DiagnosisList -Diagnoses $catalog)
        if (-not $Case) { Write-Host ''; Write-Host '用法: winmedic.ps1 diagnose --case <id>' }
        return $script:EXIT.OK
    }
    $one = Get-DiagnosisById -Id $Case
    if (-not $one) { Write-Log ('未知诊断用例: ' + $Case) -Level ERROR; return $script:EXIT.USAGE }
    if ($From) {
        if (-not (Test-Path -LiteralPath $From)) { Write-Log ('找不到文件: ' + $From) -Level ERROR; return $script:EXIT.USAGE }
        $picked = @{ path = $From; findings = (Get-Content -LiteralPath $From -Raw -Encoding UTF8 | ConvertFrom-Json); coverage = @($one.requiredProbes).Count; total = @($one.requiredProbes).Count }
    } else {
        $picked = Resolve-FindingsForDiagnosis -RequiredProbes @($one.requiredProbes)
    }
    if (-not $picked) { Write-Log '没有 findings，请先 probe' -Level ERROR; return $script:EXIT.PRECONDITION }
    $findings = $picked.findings
    if ($picked.coverage -lt $picked.total) {
        Write-Log ('选用的 findings 覆盖 ' + $picked.coverage + '/' + $picked.total + ' 个所需探针：' + [IO.Path]::GetFileName($picked.path)) -Level WARN
    }
    $trend = @((Get-TrendRecords).records)
    $res = Resolve-DiagnosisFacts -Diagnosis $one -Findings $findings -TrendRecords $trend
    if ($Json) { Write-JsonResult -Object $res | Out-Null; return $script:EXIT.OK }
    Write-Host (Format-DiagnosisReport -Result $res)
    return $script:EXIT.OK
}

function Invoke-ToolsCmd {
    $status = @(Get-ToolsStatus)
    if ($Json) { Write-JsonResult -Object @{ tools = @($status); availableCount = @($status | Where-Object { $_.available }).Count; total = @($status).Count } | Out-Null; return $script:EXIT.OK }
    Write-Host (Format-ToolsReport -Status $status)
    return $script:EXIT.OK
}

function Invoke-SelfTestCmd {
    $res = Invoke-WinMedicSelfTest -Keep:$Keep
    if ($Json) { Write-JsonResult -Object $res | Out-Null; if ($res.ok) { return $script:EXIT.OK } else { return $script:EXIT.FAIL } }
    Write-Host (Format-SelfTestReport -Result $res)
    if ($res.ok) { return $script:EXIT.OK } else { return $script:EXIT.FAIL }
}

function Invoke-RemoteApplyCmd {
    if (-not $Target) { Write-Log 'remote-apply 需要 --target <ssh 别名>' -Level ERROR; return $script:EXIT.USAGE }
    if (-not $PlanPath) { Write-Log 'remote-apply 需要 --plan <本地计划文件>' -Level ERROR; return $script:EXIT.USAGE }
    if (-not $Ids -or $Ids.Count -eq 0) { Write-Log 'remote-apply 需要 --ids <R2,R3>' -Level ERROR; return $script:EXIT.USAGE }
    if (-not $Yes) { Write-Log 'remote-apply 需要显式 --yes' -Level ERROR; return $script:EXIT.USAGE }
    $res = Invoke-RemoteApplySession -Target $Target -PlanPath $PlanPath -Ids $Ids -TimeoutSec $TimeoutSec -Keep:$Keep
    if ($Json) { Write-JsonResult -Object $res | Out-Null; if ($null -ne $res.exitCode) { return $res.exitCode } else { return $script:EXIT.REMOTE } }
    if (-not $res.ok) { Write-Log ('远端执行失败: ' + $res.output) -Level ERROR; if ($null -ne $res.exitCode) { return $res.exitCode } else { return $script:EXIT.REMOTE } }
    Write-Log ('远端执行完成，runId=' + $res.runId) -Level OK
    Write-Host ('  远端输出:')
    ($res.output -split "`r?`n") | Select-Object -Last 5 | ForEach-Object { Write-Host ('    ' + $_.Trim()) }
    if ($res.journalPath) { Write-Host ('  审计日志已拉回: ' + $res.journalPath) }
    if ($res.dir) { Write-Host ('  远端暂存目录已清理: ' + $res.dir) }
    return $script:EXIT.OK
}

function Invoke-RemoteRestoreCmd {
    if (-not $Target) { Write-Log 'remote-restore 需要 --target <ssh 别名>' -Level ERROR; return $script:EXIT.USAGE }
    if (-not $Journal) { Write-Log 'remote-restore 需要 --journal <runId>' -Level ERROR; return $script:EXIT.USAGE }
    if (-not $Yes) { Write-Log 'remote-restore 需要显式 --yes' -Level ERROR; return $script:EXIT.USAGE }
    $res = Invoke-RemoteRestoreSession -Target $Target -Journal $Journal -TimeoutSec $TimeoutSec
    if ($Json) { Write-JsonResult -Object $res | Out-Null; if ($null -ne $res.exitCode) { return $res.exitCode } else { return $script:EXIT.REMOTE } }
    if (-not $res.ok) { Write-Log ('远端还原失败: ' + $res.output) -Level ERROR; if ($null -ne $res.exitCode) { return $res.exitCode } else { return $script:EXIT.REMOTE } }
    Write-Log ('远端还原完成（journal=' + $Journal + '）') -Level OK
    ($res.output -split "`r?`n") | Select-Object -Last 4 | ForEach-Object { Write-Host ('    ' + $_.Trim()) }
    return $script:EXIT.OK
}

function Show-Help {
    Write-Host 'WinMedic 引擎'
    Write-Host '  doctor                     环境自检'
    Write-Host '  probe --set ...|workloads|relocation|intake|all'
    Write-Host '  plan  [--from findings.json] 生成方案'
    Write-Host '  apply --plan plan.json --ids R1,R2 --yes'
    Write-Host '  verify --journal <runId>   复核'
    Write-Host '  restore --journal <runId>  回滚'
    Write-Host '  journal list | journal show --journal <runId>'
    Write-Host '  profile [--exclude <模式> [--remove]]   查看/维护保留项'
    Write-Host '  report [--journal <runId>] [--out f.md] 生成五段式交付报告'
    Write-Host '  explain [--action <id>]                查看动作证据与回滚方式'
    Write-Host '  summary                                一屏体检摘要'
    Write-Host '  diff --from a.json --to b.json         两次采集对比'
    Write-Host '  relocate                               迁移策略建议（缓存/数据该不该搬）'
    Write-Host '  remote --target <别名> --set intake      远端只读采集（SSH），结果打 origin 标记'
    Write-Host '    [--via ssh|local] [--keep] [--timeout 秒]'
    Write-Host '  trend                                   病程：看谁在涨（样本不足会明说）'
    Write-Host '  trend --record [--set storage]           记录一条快照（建议每日计划任务）'
    Write-Host '    [--days 14] [--top 10]'
    Write-Host '  diagnose --list                         列出鉴别诊断用例'
    Write-Host '  diagnose --case dx.cdisk-full           鉴别诊断：只给事实与信号，不给结论'
    Write-Host '    [--from <findings.json>]              指定数据来源（例如远端采集结果）'
    Write-Host '  tools [--json]                          器械台：外部工具可用性与风险级别'
    Write-Host '  selftest [--keep]                       沙箱自检：证明隔离/还原逐字节一致'
    Write-Host '  remote-apply --target <别名> --plan <plan.json> --ids R2 --yes'
    Write-Host '                                          远端执行处置（同一套护栏；计划 origin 必须匹配）'
    Write-Host '  remote-restore --target <别名> --journal <runId> --yes'
    Write-Host '                                          远端还原（把隔离项移回远端原位）'
    Write-Host '  apply --action <id> --yes              执行 standalone 动作（仅 Tier 1）'
    Write-Host '  apply ... --purge --accept-irreversible [--confirm-token X] 物理删除（不可回滚，需确认单令牌）'
    Write-Host '  version'
    return $script:EXIT.OK
}

switch ($Command) {
    'doctor'  { $code = Invoke-Doctor }
    'probe'   { $code = Invoke-Probe }
    'plan'    { $code = Invoke-Plan }
    'apply'   { $code = Invoke-Apply }
    'verify'  { $code = Invoke-VerifyCmd }
    'restore' { $code = Invoke-Restore }
    'journal' { $code = Invoke-JournalCmd }
    'profile' { $code = Invoke-Profile }
    'report'  { $code = Invoke-Report }
    'explain' { $code = Invoke-Explain }
    'summary' { $code = Invoke-Summary }
    'diff'    { $code = Invoke-Diff }
    'relocate' { $code = Invoke-Relocate }
    'remote'  { $code = Invoke-RemoteCmd }
    'trend'   { $code = Invoke-TrendCmd }
    'diagnose' { $code = Invoke-DiagnoseCmd }
    'tools'   { $code = Invoke-ToolsCmd }
    'selftest' { $code = Invoke-SelfTestCmd }
    'remote-apply' { $code = Invoke-RemoteApplyCmd }
    'remote-restore' { $code = Invoke-RemoteRestoreCmd }
    'version' { Write-Host ('winmedic ' + (Get-Content (Join-Path $script:WinMedicRoot 'VERSION') -Raw).Trim()); $code = $script:EXIT.OK }
    default   { $code = Show-Help }
}
exit $code