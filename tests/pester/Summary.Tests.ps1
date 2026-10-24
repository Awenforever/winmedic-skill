#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Summary.ps1')
    . (Join-Path $repo 'engine\lib\Recommendations.ps1')
    function New-FullFindings {
        [pscustomobject]@{
            generatedAt = '2026-10-24T01:00:00+08:00'
            probeSet = 'intake'
            host = [pscustomobject]@{ computerName = 'PC1'; osCaption = 'Windows 11 Pro'; osBuild = '26200' }
            probes = @(
                [pscustomobject]@{ id = 'probe.drive-space'; ok = $true; data = [pscustomobject]@{ total = 250GB; free = 200GB; used = 50GB; usedPercent = 20 } },
                [pscustomobject]@{ id = 'probe.startup-items'; ok = $true; data = [pscustomobject]@{ count = 10; items = @([pscustomobject]@{ advice = 'optional-disable' }, [pscustomobject]@{ advice = 'keep' }) } },
                [pscustomobject]@{ id = 'probe.perf-baseline'; ok = $true; data = [pscustomobject]@{ verdict = 'ok' } },
                [pscustomobject]@{ id = 'probe.windows-update'; ok = $true; data = [pscustomobject]@{ pendingReboot = [pscustomobject]@{ pending = $false } } },
                [pscustomobject]@{ id = 'probe.drivers'; ok = $true; data = [pscustomobject]@{ problemCount = 0 } },
                [pscustomobject]@{ id = 'probe.security-posture'; ok = $true; data = [pscustomobject]@{ verdict = 'ok'; issues = @() } },
                [pscustomobject]@{ id = 'probe.recovery-readiness'; ok = $true; data = [pscustomobject]@{ level = 'ready'; risks = @() } },
                [pscustomobject]@{ id = 'probe.backup-status'; ok = $true; data = [pscustomobject]@{ level = 'ok'; sources = @('OneDrive 文件夹备份') } },
                [pscustomobject]@{ id = 'probe.printers'; ok = $true; data = [pscustomobject]@{ count = 2; problemCount = 0 } }
            )
        }
    }
    function New-EmptyFindings {
        [pscustomobject]@{
            generatedAt = '2026-10-24T01:00:00+08:00'
            probeSet = 'storage'
            host = [pscustomobject]@{ computerName = 'PC2'; osCaption = 'Windows'; osBuild = '1' }
            probes = @()
        }
    }
}

Describe '摘要行' {
    It '九个领域各一行' {
        $lines = Get-SummaryLines -Findings (New-FullFindings)
        @($lines).Count | Should -Be 9
    }
    It '缺少探针时标为 unknown 而不是报错' {
        $lines = Get-SummaryLines -Findings (New-EmptyFindings)
        ($lines | Where-Object { $_.verdict -eq 'unknown' }).Count | Should -Be 9
    }
    It '磁盘使用率高时为 warn' {
        $f = New-FullFindings
        $f.probes[0].data.usedPercent = 95
        $line = (Get-SummaryLines -Findings $f | Where-Object { $_.domain -eq '磁盘' })
        $line.verdict | Should -Be 'warn'
    }
    It '待重启会拉低更新域判定' {
        $f = New-FullFindings
        $f.probes[3].data.pendingReboot.pending = $true
        $line = (Get-SummaryLines -Findings $f | Where-Object { $_.domain -eq '更新' })
        $line.verdict | Should -Be 'warn'
    }
    It '恢复等级 poor 时为 bad' {
        $f = New-FullFindings
        $f.probes[6].data.level = 'poor'
        $f.probes[6].data.risks = @('没有系统还原点')
        $line = (Get-SummaryLines -Findings $f | Where-Object { $_.domain -eq '恢复' })
        $line.verdict | Should -Be 'bad'
    }
}

Describe '摘要渲染' {
    It '包含主机与全部领域标签' {
        $md = Format-WinMedicSummary -Findings (New-FullFindings)
        $md | Should -Match 'PC1'
        foreach ($d in @('磁盘', '启动', '应用', '更新', '网络', '安全', '恢复', '备份', '外设')) {
            $md | Should -Match $d
        }
    }
}

Describe '摘要中的建议' {
    It '有建议时渲染建议段并标注可执行动作' {
        $f = New-FullFindings
        $f.probes[6].data.level = 'poor'
        $f.probes[6].data.risks = @('没有系统还原点')
        $md = Format-WinMedicSummary -Findings $f
        $md | Should -Match '建议:'
        $md | Should -Match '先建系统还原点'
        $md | Should -Match 'recovery.create-restore-point'
    }
    It '无建议时不渲染建议段' {
        $f = New-FullFindings
        $f.probes[1].data.items = @([pscustomobject]@{ advice = 'keep' })
        $md = Format-WinMedicSummary -Findings $f
        $md | Should -Not -Match '建议:'
    }
}

Describe '采集对比' {
    It '抽取关键指标' {
        $m = Get-DiffMetrics -Findings (New-FullFindings)
        $m['启动项数'] | Should -Be 10
        $m['可用空间GB'] | Should -Be 200
    }
    It '对比表显示变化' {
        $a = New-FullFindings
        $b = New-FullFindings
        $b.probes[0].data.free = 150GB
        $b.probes[1].data.count = 16
        $txt = Format-FindingsDiff -Before $a -After $b
        $txt | Should -Match '启动项数'
        $txt | Should -Match '-50'
        $txt | Should -Match '\+6'
    }
}