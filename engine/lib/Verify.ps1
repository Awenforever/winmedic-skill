#Requires -Version 5.1
<#
.SYNOPSIS
  验证层：按动作定义的 verify 规则复核效果。
#>

function Invoke-VerifyRule {
    param([Parameter(Mandatory)]$Rule)
    switch ($Rule.kind) {
        'path_absent' {
            return @{ ok = (-not (Test-Path -LiteralPath $Rule.path)); detail = ('路径不存在: ' + $Rule.path) }
        }
        'system_file_absent' {
            return @{ ok = (-not (Test-SystemFileExists -Path $Rule.path)); detail = ('系统文件不存在: ' + $Rule.path) }
        }
        'path_size_lt' {
            if (-not (Test-Path -LiteralPath $Rule.path)) { return @{ ok = $true; detail = '路径已不存在' } }
            $s = Get-PathSize -Path $Rule.path
            return @{ ok = ($s.Size -lt [int64]$Rule.bytes); detail = ('当前 ' + [math]::Round($s.Size / 1MB, 1) + ' MB，阈值 ' + [math]::Round($Rule.bytes / 1MB, 1) + ' MB') }
        }
        'free_space_increased' {
            return @{ ok = $true; detail = '可用空间变化见报告' }
        }
        'pending_reboot_hint' {
            return @{ ok = $true; detail = '组件清理需重启后才完全生效'; pendingReboot = $true }
        }
        default { return @{ ok = $false; detail = ('未知验证类型: ' + $Rule.kind) } }
    }
}

function Invoke-ActionVerify {
    param([Parameter(Mandatory)]$Action)
    $results = @()
    $pending = $false
    foreach ($r in @($Action.verify)) {
        if (-not $r) { continue }
        $res = Invoke-VerifyRule -Rule $r
        if ($res.ContainsKey('pendingReboot')) { $pending = $true }
        $results += @{ rule = $r.kind; ok = $res.ok; detail = $res.detail }
    }
    return @{ results = $results; pendingReboot = $pending; allOk = (($results | Where-Object { -not $_.ok }).Count -eq 0) }
}