#Requires -Version 5.1
<#
.SYNOPSIS
  在当前用户的交互式会话里执行一次性脚本（用于 session 0 读不到的音频端点等）。
.NOTES
  通过计划任务实现：注册为当前用户、交互式运行，执行完立即删除任务。
  写操作仅限临时脚本与临时输出文件，不修改系统设置。
#>

function Invoke-InUserSession {
    param([string]$ScriptPath, [string[]]$ScriptArgs = @(), [string]$OutFile, [int]$TimeoutSec = 20)
    $tn = 'WinMedic_UserSession_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ScriptPath + '"'
    if ($ScriptArgs -and $ScriptArgs.Count -gt 0) { $arg += ' ' + ($ScriptArgs -join ' ') }
    try {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(5))
        Register-ScheduledTask -TaskName $tn -Action $action -Trigger $trigger -Force | Out-Null
        Start-ScheduledTask -TaskName $tn
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            if (Test-Path -LiteralPath $OutFile) { break }
            Start-Sleep -Milliseconds 400
        }
        $ok = Test-Path -LiteralPath $OutFile
        return [pscustomobject]@{ ok = $ok; taskName = $tn; error = $(if ($ok) { '' } else { '用户会话脚本未在 ' + $TimeoutSec + ' 秒内产出结果（可能没有交互式登录会话，或被组策略拦截）' }) }
    } catch {
        return [pscustomobject]@{ ok = $false; taskName = $tn; error = $_.Exception.Message }
    } finally {
        Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue
    }
}
