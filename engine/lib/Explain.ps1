#Requires -Version 5.1
<#
.SYNOPSIS
  不可逆操作确认单：用大白话把每一项讲清楚，再让用户回填令牌。
.DESCRIPTION
  目的：确保完全没有技术背景的用户也能看懂「要删什么、为什么能删、删了会怎样」。
  令牌不是防呆，而是强制流程：DSH 必须先把单子展示给用户，才可能拿到令牌。
#>

function Get-PlainExplanation {
    param($Action = $null, [string]$ActionId = '')
    if ($Action -and ($Action.PSObject.Properties.Name -contains 'plain') -and $Action.plain) {
        $p = $Action.plain
        return @{ what = [string]$p.what; why = [string]$p.why; consequence = [string]$p.consequence }
    }
    $idText = if ($ActionId) { $ActionId } else { '未知动作' }
    return @{
        what = ('动作 ' + $idText)
        why = 'catalog 未提供通俗说明，按不可逆处理'
        consequence = '无法说明后果，请先用 explain 查看或改用非 purge 模式'
    }
}

function New-PurgeConfirmationToken {
    param([string]$PlanHash = '', [string[]]$Ids = @())
    $material = 'purge|' + $PlanHash + '|' + (($Ids | Sort-Object) -join ',') + '|' + @($Ids).Count
    $h = Get-StringSha256 -Text $material
    return $h.Substring(0, 8).ToUpperInvariant()
}

function Format-PurgeConfirmation {
    param([array]$Items = @(), [string]$PlanHash = '', [string]$Token = '')
    $sb = New-Object System.Text.StringBuilder
    $totalBytes = 0L
    foreach ($it in $Items) { if ($it.sizeBytes) { $totalBytes += [int64]$it.sizeBytes } }
    $totalGb = [math]::Round($totalBytes / 1GB, 2)
    $short = $PlanHash
    if ($short.Length -gt 8) { $short = $short.Substring(0, 8) }

    [void]$sb.AppendLine('================ 不可逆操作确认单 ================')
    [void]$sb.AppendLine('下面这些内容将被【永久删除】，删除后无法通过 WinMedic 恢复。')
    [void]$sb.AppendLine(('共 ' + @($Items).Count + ' 项，合计约 ' + $totalGb + ' GB。计划指纹：' + $short))
    [void]$sb.AppendLine('')

    $i = 0
    foreach ($it in $Items) {
        $i++
        $ex = Get-PlainExplanation -Action $it.action -ActionId ([string]$it.actionId)
        $sizeText = '未知'
        if ($it.sizeBytes) { $sizeText = ([math]::Round([int64]$it.sizeBytes / 1MB, 1).ToString() + ' MB') }
        [void]$sb.AppendLine(('[' + $i + '/' + @($Items).Count + '] ' + $it.id + '  ' + $it.actionId))
        [void]$sb.AppendLine('  这是什么    ：' + $ex.what)
        [void]$sb.AppendLine('  在哪里      ：' + $it.target)
        [void]$sb.AppendLine('  有多大      ：' + $sizeText)
        [void]$sb.AppendLine('  为什么可以删：' + $ex.why)
        [void]$sb.AppendLine('  删了会怎样  ：' + $ex.consequence)
        [void]$sb.AppendLine('  能不能撤回  ：不能（本次为物理删除，不经过隔离区）')
        [void]$sb.AppendLine('')
    }

    [void]$sb.AppendLine('-------------------------------------------------')
    [void]$sb.AppendLine('如果以上每一项你都已经看懂并同意，把下面的令牌原样回填即可执行：')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  --confirm-token ' + $Token)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('有任何一项看不懂就不要执行——改用不带 --purge 的普通模式（走隔离区，可恢复）。')
    [void]$sb.AppendLine('=================================================')
    return $sb.ToString().TrimEnd()
}
