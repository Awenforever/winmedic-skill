#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\probes\media.ps1')
}

Describe '媒体时间偏移计算' {
    It '正常时间返回接近 0 的偏移' {
        $ft = Get-Date '2026-11-01 13:01:49'
        $off = Convert-MediaOffsetHours -FileTime $ft -MetaText '2026/11/1 13:01:00'
        [math]::Abs([double]$off) | Should -BeLessThan 0.1
    }
    It '元数据 +8 小时能识别' {
        $ft = Get-Date '2026-11-01 13:01:49'
        $off = Convert-MediaOffsetHours -FileTime $ft -MetaText '2026/11/1 21:01:00'
        [double]$off | Should -BeGreaterThan 7
    }
    It '无法解析返回 null' {
        $ft = Get-Date
        Convert-MediaOffsetHours -FileTime $ft -MetaText '' | Should -BeNullOrEmpty
        Convert-MediaOffsetHours -FileTime $ft -MetaText 'not-a-date' | Should -BeNullOrEmpty
    }
}

Describe '媒体时间探针' {
    It '空目录返回 0 样本而不是报错' {
        $tmp = Join-Path $TestDrive 'empty-media'
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $p = Get-MediaTimestampProbe -Paths @($tmp) -MaxFiles 5 -TimeBudgetSeconds 5
        $p.id | Should -Be 'probe.media-timestamps'
        $p.ok | Should -BeTrue
        [int]$p.data.sampled | Should -Be 0
        [int]$p.data.shifted | Should -Be 0
    }
}