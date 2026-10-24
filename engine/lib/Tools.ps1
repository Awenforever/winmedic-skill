#Requires -Version 5.1
<#
.SYNOPSIS
  器械台：登记外部工具怎么检测、静默参数、风险级别。
.NOTES
  只做检测与说明，不执行高危动作。Tier>=3 的器械必须由 Agent 显式计划后调用。
#>

function Get-ToolCatalog {
    param([string]$Path = '')
    if (-not $Path) {
        $root = $script:WinMedicRoot
        if (-not $root) { $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
        $Path = Join-Path $root 'catalog\tools.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($raw.tools)
}

function Test-ToolAvailable {
    param([Parameter(Mandatory)]$Tool)
    $type = [string]$Tool.detect.type
    $value = [string]$Tool.detect.value
    switch ($type) {
        'command' {
            $c = Get-Command $value -ErrorAction SilentlyContinue
            if ($c) { return @{ available = $true; detail = [string]$c.Source } }
            return @{ available = $false; detail = '未找到命令' }
        }
        'path' {
            if (Test-Path -LiteralPath $value) { return @{ available = $true; detail = $value } }
            return @{ available = $false; detail = '路径不存在' }
        }
        'registry' {
            if (Test-Path -LiteralPath $value) { return @{ available = $true; detail = $value } }
            return @{ available = $false; detail = '注册表项不存在' }
        }
        default { return @{ available = $false; detail = ('未知检测类型: ' + $type) } }
    }
}

function Get-ToolsStatus {
    param([string]$Path = '')
    $out = @()
    foreach ($t in (Get-ToolCatalog -Path $Path)) {
        $a = Test-ToolAvailable -Tool $t
        $out += [pscustomobject]@{
            id = [string]$t.id
            name = [string]$t.name
            category = [string]$t.category
            available = $a.available
            detail = $a.detail
            tier = if ($t.risk) { [int]$t.risk.tier } else { 0 }
            reversible = if ($t.risk) { [bool]$t.risk.reversible } else { $false }
            notes = [string]$t.notes
        }
    }
    return $out
}

function Format-ToolsReport {
    param([array]$Status = @())
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| 器械 | 类别 | 可用 | 级别 | 可回滚 | 说明 |')
    [void]$sb.AppendLine('|---|---|---|---:|---|---|')
    foreach ($s in $Status) {
        $ok = if ($s.available) { '是' } else { '否' }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $s.name, $s.category, $ok, $s.tier, $s.reversible, $s.notes))
    }
    $missing = @($Status | Where-Object { -not $_.available })
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('可用 ' + (@($Status).Count - $missing.Count) + '/' + @($Status).Count + '。Tier>=3 的器械必须显式计划后再调用。'))
    return $sb.ToString().TrimEnd()
}
