#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Trend.ps1')
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
    function New-Findings2 {
        param([double]$free = 93, [double]$hiber = 6.4, [double]$wl = 2.75)
        [pscustomobject]@{
            probeSet = 'storage'
            probes = @(
                [pscustomobject]@{ id = 'probe.host'; data = [pscustomobject]@{ computerName = 'H1' } },
                [pscustomobject]@{ id = 'probe.drive-space'; data = [pscustomobject]@{ letter = 'C:'; total = 237GB; free = ($free * 1GB); usedPercent = 60 } },
                [pscustomobject]@{ id = 'probe.system-files'; data = [pscustomobject]@{ hiberfilSize = ($hiber * 1GB) } },
                [pscustomobject]@{ id = 'probe.browser-cache'; data = [pscustomobject]@{ total = 0.5GB } },
                [pscustomobject]@{ id = 'probe.workloads'; data = [pscustomobject]@{ totalCacheBytes = ($wl * 1GB); workloads = @([pscustomobject]@{ id = 'workload.steam'; installed = $true; cacheBytes = 0.15GB }) } }
            )
        }
    }
}
AfterAll { Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue }

Describe '快照生成' {
    It '抽取卷与指标' {
        $s = Get-TrendSnapshot -Findings (New-Findings2) -Origin 'local'
        $s.host | Should -Be 'H1'
        $s.volumes[0].drive | Should -Be 'C:'
        $s.volumes[0].freeGB | Should -Be 93
        $s.metrics['volume.freeGB'] | Should -Be 93
        $s.metrics['storage.hiberfilGB'] | Should -Be 6.4
        $s.metrics['workloads.totalCacheGB'] | Should -Be 2.75
    }
    It '缺探针也不报错' {
        $f = [pscustomobject]@{ probeSet = 'x'; probes = @([pscustomobject]@{ id = 'probe.host'; data = [pscustomobject]@{ computerName = 'H' } }) }
        $s = Get-TrendSnapshot -Findings $f
        @($s.metrics.Keys).Count | Should -Be 0
        $s.origin | Should -Be 'local'
    }
}

Describe '病程数据的完整性' {
    It '序列按来源隔离，不混机' {
        $recs = @(
            [pscustomobject]@{ ts='2026-10-24T10:00:00+08:00'; origin='local'; probeSet='storage'; metrics=[pscustomobject]@{ 'volume.freeGB'=90 } },
            [pscustomobject]@{ ts='2026-10-24T10:05:00+08:00'; origin='remote:vm1'; probeSet='storage'; metrics=[pscustomobject]@{ 'volume.freeGB'=22 } }
        )
        $local = @($recs | Where-Object { $_.origin -eq 'local' })
        $local.Count | Should -Be 1
        $local[0].metrics.'volume.freeGB' | Should -Be 90
    }
    It '同一 (origin, ts, probeSet) 只记录一次' {
        $dir = Join-Path $TestDrive 'cdrive'
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'state') | Out-Null
        $env:CDRIVE_HOME = $dir
        $snap = [pscustomobject]@{ ts='2026-10-24T10:00:00+08:00'; host='H'; origin='local'; probeSet='storage'; metrics=[pscustomobject]@{ 'volume.freeGB'=90 } }
        (Add-TrendRecord -Snapshot $snap) | Should -BeTrue
        (Add-TrendRecord -Snapshot $snap) | Should -BeFalse
        @(Get-TrendRecords -Origin 'local' -Path (Join-Path $dir 'state\trend.jsonl')).Count | Should -Be 1
    }
}

Describe '清理目标纳入病程' {
    It '每个目标与合计都进快照' {
        $f = [pscustomobject]@{ probeSet = 'storage'; probes = @(
            [pscustomobject]@{ id = 'probe.host'; data = [pscustomobject]@{ computerName = 'H' } },
            [pscustomobject]@{ id = 'probe.cleanup-targets'; data = [pscustomobject]@{ items = @(
                [pscustomobject]@{ id = 'clean.cbs-logs'; size = 1073741824 },
                [pscustomobject]@{ id = 'clean.pip-cache'; size = 536870912 }) } }
        ) }
        $s = Get-TrendSnapshot -Findings $f
        $s.metrics['cleanup.cbs-logs.GB'] | Should -Be 1
        $s.metrics['cleanup.pip-cache.GB'] | Should -Be 0.5
        $s.metrics['cleanup.totalGB'] | Should -Be 1.5
    }
}

Describe '增长计算' {
    It '少于两点判 insufficient' {
        (Get-TrendGrowth -Series @() -Metric 'm').confidence | Should -Be 'insufficient'
        (Get-TrendGrowth -Series @([pscustomobject]@{ ts = '2026-10-01T00:00:00'; value = 1 }) -Metric 'm').confidence | Should -Be 'insufficient'
    }
    It '两点间隔两天时给出正确速率' {
        $s = @(
            [pscustomobject]@{ ts = '2026-10-01T00:00:00'; value = 100 },
            [pscustomobject]@{ ts = '2026-10-03T00:00:00'; value = 80 }
        )
        $g = Get-TrendGrowth -Series $s -Metric 'volume.freeGB'
        $g.points | Should -Be 2
        $g.delta | Should -Be -20
        $g.perDay | Should -Be -10
        $g.confidence | Should -Be 'ok'
    }
    It '间隔不足半天不给速率' {
        $s = @(
            [pscustomobject]@{ ts = '2026-10-01T00:00:00'; value = 100 },
            [pscustomobject]@{ ts = '2026-10-01T00:30:00'; value = 99 }
        )
        $g = Get-TrendGrowth -Series $s -Metric 'm'
        $g.confidence | Should -Be 'low'
        $g.perDay | Should -BeNullOrEmpty
    }
    It '乱序时间戳按时间排序' {
        $s = @(
            [pscustomobject]@{ ts = '2026-10-03T00:00:00'; value = 80 },
            [pscustomobject]@{ ts = '2026-10-01T00:00:00'; value = 100 }
        )
        $g = Get-TrendGrowth -Series $s -Metric 'm'
        $g.first | Should -Be 100
        $g.last | Should -Be 80
    }
}

Describe '记录与报告' {
    It '坏行被跳过且不抛错' {
        $p = Join-Path $TestDrive 'bad.jsonl'
        Set-Content -LiteralPath $p -Value @('{"ts":"2026-10-01T00:00:00","metrics":{"m":1}}', 'not-json', '{"ts":"2026-10-03T00:00:00","metrics":{"m":2}}') -Encoding UTF8
        $r = Get-TrendRecords -Path $p
        $r.records.Count | Should -Be 2
        $r.badLines | Should -Be 1
    }
    It '只有一条时明确说样本不足' {
        $txt = Format-TrendReport -Growth @() -RecordCount 1
        $txt | Should -Match '样本不足'
        $txt | Should -Match 'trend --record'
    }
    It '追加后文件行数增加' {
        $snap = Get-TrendSnapshot -Findings (New-Findings2)
        [void](Add-TrendRecord -Snapshot $snap)
        $file = Get-TrendFile
        (Get-Content -LiteralPath $file).Count | Should -BeGreaterThan 0
    }
}