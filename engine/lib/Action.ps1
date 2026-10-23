#Requires -Version 5.1
<#
.SYNOPSIS
  执行层：隔离区移动、命令执行、DISM 调用。所有写操作都从这里出去。
#>

function Get-VolumeOfPath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path.Length -ge 2 -and $Path[1] -eq ':') { return $Path.Substring(0, 2).ToUpper() }
    return ''
}

function Invoke-QuarantineMove {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ItemId
    )
    $stateDrive = Get-VolumeOfPath -Path (Get-CdriveRoot)
    $targetDrive = Get-VolumeOfPath -Path $Target
    if ($stateDrive -and $targetDrive -and ($stateDrive -ne $targetDrive)) {
        return @{ ok = $false; error = ('跨卷移动被拒绝（目标 ' + $targetDrive + '，隔离区 ' + $stateDrive + '）'); quarantinePath = '' }
    }
    if (-not (Test-Path -LiteralPath $Target)) {
        return @{ ok = $false; error = '目标不存在'; quarantinePath = '' }
    }
    $qdir = New-QuarantineDir -RunId $RunId -ItemId $ItemId
    $leaf = Split-Path -Leaf $Target
    if (-not $leaf) { $leaf = 'item' }
    $dest = Join-Path $qdir $leaf
    $suffix = 0
    while (Test-Path -LiteralPath $dest) {
        $suffix++
        $dest = Join-Path $qdir ($leaf + '.' + $suffix)
    }
    try {
        Move-Item -LiteralPath $Target -Destination $dest -Force -ErrorAction Stop
        return @{ ok = $true; error = ''; quarantinePath = $dest }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message; quarantinePath = '' }
    }
}

function Invoke-NativeCommand {
    param([Parameter(Mandatory)][string]$CommandLine)
    Set-ConsoleEncodingForCapture
    try {
        $out = & cmd.exe /c $CommandLine 2>&1
        $code = $LASTEXITCODE
    } catch {
        $out = @($_.Exception.Message)
        $code = 1
    } finally {
        Set-ConsoleEncodingForOutput
    }
    $text = ($out | Out-String)
    return @{ ok = ($code -eq 0); exitCode = $code; output = $text; outputSha256 = (Get-StringSha256 -Text $text) }
}

function Invoke-DismCleanup {
    param([Parameter(Mandatory)][string]$CommandLine, [int]$TimeoutSeconds = 3600)
    Set-ConsoleEncodingForCapture
    $job = Start-Job -ScriptBlock {
        param($cl)
        $o = & cmd.exe /c $cl 2>&1
        [pscustomobject]@{ code = $LASTEXITCODE; text = ($o | Out-String) }
    } -ArgumentList $CommandLine
    $done = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if (-not $done) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Set-ConsoleEncodingForOutput
        return @{ ok = $false; exitCode = -1; output = 'DISM 超时'; outputSha256 = '' }
    }
    $res = Receive-Job -Job $job
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    Set-ConsoleEncodingForOutput
    $text = $res.text
    return @{ ok = ($res.code -eq 0); exitCode = $res.code; output = $text; outputSha256 = (Get-StringSha256 -Text $text) }
}

function Invoke-CdriveAction {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)][string]$RunId,
        [switch]$Purge
    )
    $before = (Get-PSDrive C -ErrorAction SilentlyContinue).Free
    $result = @{ ok = $false; mode = ''; quarantinePath = ''; exitCode = 0; outputSha256 = ''; error = '' }

    switch ($Action.kind) {
        'quarantine' {
            if ($Purge) {
                try {
                    Remove-Item -LiteralPath $Item.target -Recurse -Force -ErrorAction Stop
                    $result.ok = $true; $result.mode = 'purge'
                } catch { $result.error = $_.Exception.Message }
            } else {
                $q = Invoke-QuarantineMove -Target $Item.target -RunId $RunId -ItemId $Item.id
                $result.ok = $q.ok; $result.mode = 'quarantine'; $result.quarantinePath = $q.quarantinePath; $result.error = $q.error
            }
        }
        'command' {
            $r = Invoke-NativeCommand -CommandLine $Action.command
            $result.ok = $r.ok; $result.mode = 'command'; $result.exitCode = $r.exitCode; $result.outputSha256 = $r.outputSha256
            if (-not $r.ok) { $result.error = ('退出码 ' + $r.exitCode) }
        }
        'dism' {
            $r = Invoke-DismCleanup -CommandLine $Action.command
            $result.ok = $r.ok; $result.mode = 'dism'; $result.exitCode = $r.exitCode; $result.outputSha256 = $r.outputSha256
            if (-not $r.ok) { $result.error = ('退出码 ' + $r.exitCode) }
        }
        default { $result.error = ('未知动作类型: ' + $Action.kind) }
    }

    $after = (Get-PSDrive C -ErrorAction SilentlyContinue).Free
    $result['freeBefore'] = [int64]$before
    $result['freeAfter'] = [int64]$after
    return $result
}