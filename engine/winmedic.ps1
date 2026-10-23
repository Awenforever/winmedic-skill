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
    [ValidateSet('doctor', 'probe', 'plan', 'apply', 'verify', 'restore', 'journal', 'profile', 'report', 'version', 'help')]
    [string]$Command = 'help',
    [Parameter(Position = 1)]
    [string]$SubCommand,
    [string]$Set = 'storage',
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
    [switch]$Remove,
    [switch]$Json
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
    $set = $Set.ToLower()
    $probes = @()
    $probes += (Get-HostProbe)

    if ($set -eq 'storage' -or $set -eq 'all') {
        $probes += @(
            (Get-DriveSpaceProbe), (Get-SystemFilesProbe), (Get-RecycleBinProbe),
            (Get-UpdateLeftoversProbe), (Get-PackageCacheProbe), (Get-BrowserCacheProbe),
            (Get-OfficeCacheProbe), (Get-AppCachesProbe)
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

    if ($set -eq 'intake') {
        $probes += (Get-DriveSpaceProbe)
    }

    if ($probes.Count -le 1) {
        Write-Log ('未知探针集: ' + $Set + '（可用 storage / boot / apps / updates / network / security / recovery / printers / backup / intake / all）') -Level ERROR
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
    $src = if ($From) { $From } else { Get-StatePath 'findings.json' }
    if (-not (Test-Path -LiteralPath $src)) {
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
    $p = if ($PlanPath) { $PlanPath } else { Get-StatePath 'plan.json' }
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Log ('找不到 plan：' + $p) -Level ERROR
        return $script:EXIT.USAGE
    }
    if (-not $Yes) {
        Write-Log 'apply 需要显式 --yes 才执行' -Level ERROR
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
        $r = Invoke-CdriveAction -Item $it -Action $act -RunId $runId -Purge:$Purge
        $ver = Invoke-ActionVerify -Action $act
        $recResult = if ($r.alreadyAbsent) { 'skipped' } else { 'ok' }
            itemId = $it.id; actionId = $it.actionId; target = $it.target; kind = $act.kind
            mode = $r.mode; ok = $r.ok; error = $r.error; quarantinePath = $r.quarantinePath
            exitCode = $r.exitCode; outputSha256 = $r.outputSha256
            freeBefore = $r.freeBefore; freeAfter = $r.freeAfter
            verifyAllOk = $ver.allOk; pendingReboot = $ver.pendingReboot; verify = $ver.results
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
    $out = @()
    foreach ($r in $recs) {
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
        $q = $r.quarantinePath
        if (-not $q -or -not (Test-Path -LiteralPath $q)) { continue }
        $dest = $r.target
        if (Test-Path -LiteralPath $dest) {
            Write-Log ('目标已存在，跳过: ' + $dest) -Level WARN; $failed++; continue
        }
        $parent = Split-Path -Parent $dest
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        try {
            Move-Item -LiteralPath $q -Destination $dest -Force -ErrorAction Stop
            Write-Log ('已恢复: ' + $dest) -Level OK
            $restored++
            Write-JournalRecord -RunId $Journal -Record @{ itemId = $r.itemId; actionId = $r.actionId; target = $dest; result = 'restored' }
        } catch {
            Write-Log ('恢复失败: ' + $dest + ' -> ' + $_.Exception.Message) -Level ERROR
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
    $state = Get-StatePath
    $candidates = @(
        (Join-Path $state ($Set + '-findings.json')),
        (Join-Path $state 'findings.json')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    $newest = Get-ChildItem -LiteralPath $state -Filter '*-findings.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest) { return $newest.FullName }
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

function Show-Help {
    Write-Host 'WinMedic 引擎'
    Write-Host '  doctor                     环境自检'
    Write-Host '  probe --set storage|boot|apps|updates|network|security|recovery|printers|backup|intake|all'
    Write-Host '  plan  [--from findings.json] 生成方案'
    Write-Host '  apply --plan plan.json --ids R1,R2 --yes'
    Write-Host '  verify --journal <runId>   复核'
    Write-Host '  restore --journal <runId>  回滚'
    Write-Host '  journal list | journal show --journal <runId>'
    Write-Host '  profile [--exclude <模式> [--remove]]   查看/维护保留项'
    Write-Host '  report [--journal <runId>] [--out f.md] 生成五段式交付报告'
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
    'version' { Write-Host ('winmedic ' + (Get-Content (Join-Path $script:WinMedicRoot 'VERSION') -Raw).Trim()); $code = $script:EXIT.OK }
    default   { $code = Show-Help }
}
exit $code