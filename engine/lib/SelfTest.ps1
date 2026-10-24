#Requires -Version 5.1
<#
.SYNOPSIS
  沙箱自检：用真实代码路径证明「可回滚」。
.DESCRIPTION
  不碰任何系统文件。在 CDRIVE_HOME\sandbox 下造一棵目录树，然后：
    1. 走 Invoke-QuarantineMove 隔离它（真实函数）
    2. 校验隔离区里的内容哈希与原树一致
    3. 走 Restore-JournalQuarantine 还原
    4. 校验还原后哈希与原树完全一致（字节级）
    5. 再测一次「预写日志中断」的孤儿恢复
  任何一步不符预期即判失败。
#>

function Get-SandboxHashes {
    param([Parameter(Mandatory)][string]$Root)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Root)) { return $map }
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
        $map[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    return $map
}

function New-SandboxTree {
    param([Parameter(Mandatory)][string]$Root)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'nested') | Out-Null
    Set-Content -LiteralPath (Join-Path $Root 'a.txt') -Value 'winmedic sandbox alpha' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Root 'nested\b.log') -Value ('x' * 4096) -Encoding UTF8
    $bytes = New-Object byte[] 1024
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [byte]($i % 251) }
    [IO.File]::WriteAllBytes((Join-Path $Root 'c.bin'), $bytes)
    return $Root
}

function Invoke-WinMedicSelfTest {
    param([switch]$Keep)
    $checks = @()
    $runId = 'selftest-' + (Get-Date).ToString('yyyyMMdd-HHmmss')
    $sandbox = Join-Path (Get-CdriveRoot) ('sandbox\' + $runId)
    $targetA = Join-Path $sandbox 'targetA'
    $targetB = Join-Path $sandbox 'targetB'
    try {
        [void](New-SandboxTree -Root $targetA)
        $before = Get-SandboxHashes -Root $targetA
        $checks += [pscustomobject]@{ name = 'sandbox-created'; ok = ($before.Count -ge 3); detail = ('' + $before.Count + ' 个文件') }

        Write-JournalRecord -RunId $runId -Record @{ itemId = 'S1'; actionId = 'selftest.quarantine'; target = $targetA; phase = 'begin' }
        $mv = Invoke-QuarantineMove -Target $targetA -RunId $runId -ItemId 'S1'
        $checks += [pscustomobject]@{ name = 'quarantine-move'; ok = [bool]$mv.ok; detail = [string]$mv.error }
        $checks += [pscustomobject]@{ name = 'target-removed'; ok = (-not (Test-Path -LiteralPath $targetA)); detail = $targetA }

        $afterMove = [ordered]@{}
        if ($mv.ok -and (Test-Path -LiteralPath $mv.quarantinePath)) { $afterMove = Get-SandboxHashes -Root $mv.quarantinePath }
        $sameCount = ($afterMove.Count -eq $before.Count)
        $sameHash = $true
        foreach ($k in $before.Keys) { if (-not $afterMove.Contains($k) -or $afterMove[$k] -ne $before[$k]) { $sameHash = $false } }
        $checks += [pscustomobject]@{ name = 'quarantine-integrity'; ok = ($sameCount -and $sameHash); detail = ('' + $afterMove.Count + ' 个文件，哈希一致=' + $sameHash) }

        Write-JournalRecord -RunId $runId -Record @{ itemId = 'S1'; actionId = 'selftest.quarantine'; target = $targetA; phase = 'done'; quarantinePath = $mv.quarantinePath }
        $rec = [pscustomobject]@{ itemId = 'S1'; target = $targetA; quarantinePath = $mv.quarantinePath }
        $rs = Restore-JournalQuarantine -Record $rec
        $checks += [pscustomobject]@{ name = 'restore'; ok = [bool]$rs.ok; detail = [string]$rs.detail }

        $afterRestore = Get-SandboxHashes -Root $targetA
        $identical = ($afterRestore.Count -eq $before.Count)
        foreach ($k in $before.Keys) { if (-not $afterRestore.Contains($k) -or $afterRestore[$k] -ne $before[$k]) { $identical = $false } }
        $checks += [pscustomobject]@{ name = 'restore-byte-identical'; ok = $identical; detail = ('' + $afterRestore.Count + '/' + $before.Count + ' 个文件逐字节一致=' + $identical) }

        # 孤儿恢复：只写 begin，隔离区有内容
        [void](New-SandboxTree -Root $targetB)
        $beforeB = Get-SandboxHashes -Root $targetB
        $orphanRun = $runId + '-orphan'
        Write-JournalRecord -RunId $orphanRun -Record @{ itemId = 'S9'; actionId = 'selftest.orphan'; target = $targetB; phase = 'begin' }
        $mv2 = Invoke-QuarantineMove -Target $targetB -RunId $orphanRun -ItemId 'S9'
        $orphans = @(Get-JournalOrphans -RunId $orphanRun)
        $checks += [pscustomobject]@{ name = 'orphan-detected'; ok = ($orphans.Count -eq 1 -and $orphans[0].hasQuarantine); detail = ('' + $orphans.Count + ' 项') }

        $restoredOrphan = $false
        if ($orphans.Count -eq 1) {
            $children = @(Get-ChildItem -LiteralPath $orphans[0].quarantinePath -Force -ErrorAction SilentlyContinue)
            if ($children.Count -eq 1) {
                $rr = Restore-JournalQuarantine -Record ([pscustomobject]@{ itemId = 'S9'; target = $orphans[0].target; quarantinePath = $children[0].FullName })
                $restoredOrphan = [bool]$rr.ok
            }
        }
        $afterB = Get-SandboxHashes -Root $targetB
        $sameB = ($afterB.Count -eq $beforeB.Count)
        foreach ($k in $beforeB.Keys) { if (-not $afterB.Contains($k) -or $afterB[$k] -ne $beforeB[$k]) { $sameB = $false } }
        $checks += [pscustomobject]@{ name = 'orphan-restored'; ok = ($restoredOrphan -and $sameB); detail = ('还原=' + $restoredOrphan + ' 字节一致=' + $sameB) }

        $failed = @($checks | Where-Object { -not $_.ok })
        return [pscustomobject]@{
            ok = ($failed.Count -eq 0)
            runId = $runId
            sandbox = $sandbox
            checks = @($checks)
            failedCount = $failed.Count
        }
    } finally {
        if (-not $Keep -and (Test-Path -LiteralPath $sandbox)) {
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Format-SelfTestReport {
    param([Parameter(Mandatory)]$Result)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# 沙箱自检：可回滚性证明')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 检查 | 结果 | 说明 |')
    [void]$sb.AppendLine('|---|---|---|')
    foreach ($c in @($Result.checks)) {
        $mark = if ($c.ok) { 'PASS' } else { 'FAIL' }
        [void]$sb.AppendLine(('| {0} | {1} | {2} |' -f $c.name, $mark, $c.detail))
    }
    [void]$sb.AppendLine('')
    if ($Result.ok) { [void]$sb.AppendLine('结论：隔离与还原逐字节一致，可回滚性成立。') }
    else { [void]$sb.AppendLine('结论：存在失败项，可回滚性未达标准。') }
    return $sb.ToString().TrimEnd()
}
