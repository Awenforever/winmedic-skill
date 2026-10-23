#Requires -Version 5.1
<#
.SYNOPSIS
  用户偏好：保留项（exclude）与自动确认策略。
.NOTES
  保留项是硬约束：plan 阶段排除，apply 阶段再次拦截（双层）。
#>

function Get-ProfilePath {
    return (Join-Path (Get-CdriveRoot) 'profile.json')
}

function Get-CdriveProfile {
    $p = Get-ProfilePath
    if (-not (Test-Path -LiteralPath $p)) {
        return [ordered]@{ schemaVersion = 1; exclude = @(); note = 'exclude 为通配符路径，命中的目标永不进入方案' }
    }
    try {
        $raw = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $ex = @()
        if ($raw.exclude) { $ex = @($raw.exclude) }
        return [ordered]@{ schemaVersion = 1; exclude = $ex; note = 'exclude 为通配符路径，命中的目标永不进入方案' }
    } catch {
        return [ordered]@{ schemaVersion = 1; exclude = @(); note = ('profile.json 解析失败: ' + $_.Exception.Message) }
    }
}

function Save-CdriveProfile {
    param([Parameter(Mandatory)]$Profile)
    $p = Get-CdrivePathEnsure
    $json = $Profile | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Get-ProfilePath), $json, (New-Object Text.UTF8Encoding($false)))
    return (Get-ProfilePath)
}

function Get-CdrivePathEnsure {
    $root = Get-CdriveRoot
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
    return $root
}

function Test-ExcludedPath {
    <#
      纯函数：目标是否命中用户保留项。支持 * 与 ? 通配符，忽略大小写。
      空白名单返回 $false。
    #>
    param([string]$Target = '', [string[]]$Patterns = @())
    if (-not $Target) { return $false }
    if (-not $Patterns -or $Patterns.Count -eq 0) { return $false }
    $t = $Target.TrimEnd('\')
    foreach ($pat in $Patterns) {
        if (-not $pat) { continue }
        $p = $pat.TrimEnd('\')
        if ($t -like $p) { return $true }
        if ($t.StartsWith($p + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-ExclusionReason {
    param([string]$Target = '', [string[]]$Patterns = @())
    if (-not $Target) { return '' }
    $t = $Target.TrimEnd('\')
    foreach ($pat in $Patterns) {
        if (-not $pat) { continue }
        $p = $pat.TrimEnd('\')
        if ($t -like $p -or $t.StartsWith($p + '\', [StringComparison]::OrdinalIgnoreCase)) { return ('命中用户保留项: ' + $pat) }
    }
    return ''
}

function Add-CdriveExclusion {
    param([Parameter(Mandatory)][string]$Pattern)
    $prof = Get-CdriveProfile
    $ex = @($prof.exclude)
    $norm = $Pattern.Trim().TrimEnd('\')
    if ($ex -contains $norm) { return @{ changed = $false; exclude = $ex } }
    $ex += $norm
    $prof.exclude = $ex
    [void](Save-CdriveProfile -Profile $prof)
    return @{ changed = $true; exclude = $ex }
}

function Remove-CdriveExclusion {
    param([Parameter(Mandatory)][string]$Pattern)
    $prof = Get-CdriveProfile
    $norm = $Pattern.Trim().TrimEnd('\')
    $ex = @(@($prof.exclude) | Where-Object { $_ -ne $norm })
    $prof.exclude = $ex
    [void](Save-CdriveProfile -Profile $prof)
    return @{ changed = $true; exclude = $ex }
}