#Requires -Version 5.1
<#
.SYNOPSIS
  安全层：红线判定、前置检查。引擎与规则表双层防线中的硬编码那层。
#>

$script:REDLINE_PATTERNS = @(
    '\windows\winsxs',
    '\windows\installer',
    '\windows\system32',
    '\windows\syswow64',
    '\windows\winsxs\temp',
    '\program files\windowsapps',
    '\system volume information',
    '\wechat files',
    '\xwechat_files',
    '\documents\tencent files'
)

function Test-RedlinePath {
    <# 返回 $true 表示命中红线，禁止任何写操作。 #>
    param([Parameter(Mandatory)][string]$Path)
    $p = ($Path.TrimEnd('\')).ToLower()
    foreach ($pat in $script:REDLINE_PATTERNS) {
        if ($p.Contains($pat)) { return $true }
    }
    return $false
}

function Get-RedlineReason {
    param([Parameter(Mandatory)][string]$Path)
    $p = ($Path.TrimEnd('\')).ToLower()
    foreach ($pat in $script:REDLINE_PATTERNS) {
        if ($p.Contains($pat)) { return ('命中红线模式: ' + $pat) }
    }
    return ''
}

function Test-Precondition {
    <#
      支持形式：
        admin
        services-stopped:wuauserv,BITS
        process-not-running:msedge,EXCEL
      返回 @{ Name; Ok; Detail }
    #>
    param([Parameter(Mandatory)][string]$Spec)

    if ($Spec -eq 'admin') {
        $ok = Test-IsAdmin
        $detail = if ($ok) { '当前会话为管理员' } else { '需要管理员权限（当前为普通用户）' }
        return @{ Name = 'admin'; Ok = $ok; Detail = $detail }
    }

    if ($Spec -like 'commit-headroom:*') {
        $needPct = 10
        $raw = $Spec.Substring('commit-headroom:'.Length)
        [void][int]::TryParse($raw, [ref]$needPct)
        $ci = Get-CommitInfo
        if (-not $ci -or $ci.CommitLimit -le 0) {
            return @{ Name = $Spec; Ok = $false; Detail = '无法读取提交上限' }
        }
        $headroomPct = [math]::Round((($ci.CommitLimit - $ci.CommittedBytes) / $ci.CommitLimit) * 100, 1)
        $ok = ($headroomPct -ge $needPct)
        return @{ Name = $Spec; Ok = $ok; Detail = ('提交余量 ' + $headroomPct + '%，要求 >= ' + $needPct + '%') }
    }

    if ($Spec -like 'services-stopped:*') {
        $names = $Spec.Substring('services-stopped:'.Length).Split(',')
        $bad = @()
        foreach ($n in $names) {
            $svc = Get-Service -Name $n.Trim() -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne 'Stopped') { $bad += ($n.Trim() + '=' + $svc.Status) }
        }
        return @{ Name = $Spec; Ok = ($bad.Count -eq 0)
                  Detail = if ($bad.Count -eq 0) { '相关服务均已停止' } else { '仍在运行: ' + ($bad -join ', ') } }
    }

    if ($Spec -like 'process-not-running:*') {
        $names = $Spec.Substring('process-not-running:'.Length).Split(',')
        $running = @()
        foreach ($n in $names) {
            $proc = Get-Process -Name $n.Trim() -ErrorAction SilentlyContinue
            if ($proc) { $running += $n.Trim() }
        }
        return @{ Name = $Spec; Ok = ($running.Count -eq 0)
                  Detail = if ($running.Count -eq 0) { '相关进程未运行' } else { '仍在运行: ' + ($running -join ', ') } }
    }

    return @{ Name = $Spec; Ok = $false; Detail = ('未知的前置检查: ' + $Spec) }
}

function Invoke-PreconditionList {
    param([string[]]$Specs)
    $results = @()
    foreach ($s in $Specs) { $results += (Test-Precondition -Spec $s) }
    return $results
}

function Get-CommitInfo {
    <# 提交上限与已提交量，用于判断能否缩页面文件。 #>
    $m = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
    if (-not $m) { return $null }
    return @{ CommitLimit = [int64]$m.CommitLimit; CommittedBytes = [int64]$m.CommittedBytes; AvailableMBytes = [int64]$m.AvailableMBytes }
}
function Test-RiskGate {
    <#
      纯函数：在「恢复能力不足」时决定是否放行。
      规则：
        - 没有 Tier 3+ 目标 -> 放行（Tier 1/2 可回滚或可重建）
        - 有 Tier 3+ 且恢复等级 ready -> 放行
        - 有 Tier 3+ 且等级 weak/poor/unknown -> 需显式接受风险
      AcceptRisk 只对 Tier 3 生效；Tier 4 永远不放行。
    #>
    param([array]$Items = @(), [string]$RecoveryLevel = 'unknown', [switch]$AcceptRisk)
    $tier4 = @($Items | Where-Object { [int]$_.tier -ge 4 })
    if ($tier4.Count -gt 0) {
        return @{ allow = $false; reason = '包含 Tier 4 红线目标，引擎拒绝执行' }
    }
    $tier3 = @($Items | Where-Object { [int]$_.tier -ge 3 })
    if ($tier3.Count -eq 0) {
        return @{ allow = $true; reason = '无可回滚风险项' }
    }
    if ($RecoveryLevel -eq 'ready') {
        return @{ allow = $true; reason = '恢复能力就绪（有还原点或卷影副本）' }
    }
    if ($AcceptRisk) {
        return @{ allow = $true; reason = ('恢复能力为 ' + $RecoveryLevel + '，用户已显式接受风险') }
    }
    return @{ allow = $false; reason = ('含不可回滚项，但恢复能力为 ' + $RecoveryLevel + '；请先建还原点，或加 --accept-risk 显式承担') }
}
