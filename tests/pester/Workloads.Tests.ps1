#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    $script:WinMedicRoot = $repo
    . (Join-Path $repo 'engine\probes\workloads.ps1')
}

Describe '模板展开' {
    It '替换已知占位符' {
        Expand-WorkloadTemplate -Template '{root}\caches' -Roots @{ root = 'C:\App' } | Should -Be 'C:\App\caches'
    }
    It '多个占位符' {
        Expand-WorkloadTemplate -Template '{a}\{b}' -Roots @{ a = 'C:\x'; b = 'y' } | Should -Be 'C:\x\y'
    }
    It '未知占位符返回 null' {
        Expand-WorkloadTemplate -Template '{nope}\x' -Roots @{ root = 'C:\App' } | Should -BeNullOrEmpty
    }
    It '展开环境变量' {
        $out = Expand-WorkloadTemplate -Template '%WINDIR%' -Roots @{}
        $out | Should -Match 'Windows'
    }
}

Describe '缓存裁决' {
    It '分级正确' {
        Get-WorkloadVerdict -CacheBytes 0 | Should -Be 'none'
        Get-WorkloadVerdict -CacheBytes 500MB | Should -Be 'small'
        Get-WorkloadVerdict -CacheBytes 3GB | Should -Be 'notable'
        Get-WorkloadVerdict -CacheBytes 12GB | Should -Be 'heavy'
    }
}

Describe '代理链路比对' {
    It '全部一致时判定一致' {
        $r = Get-ProxyChainSummary -Layers @(
            @{ name = 'system'; value = 'http://127.0.0.1:8136' },
            @{ name = 'git'; value = 'http://127.0.0.1:8136' }
        )
        $r.consistent | Should -BeTrue
        @($r.conflicts).Count | Should -Be 0
    }
    It '端口不同即冲突（实测踩过的坑）' {
        $r = Get-ProxyChainSummary -Layers @(
            @{ name = 'system'; value = 'http://127.0.0.1:8136' },
            @{ name = 'git'; value = 'http://127.0.0.1:7890' }
        )
        $r.consistent | Should -BeFalse
        @($r.conflicts).Count | Should -Be 2
    }
    It '空层不参与比较' {
        $r = Get-ProxyChainSummary -Layers @(
            @{ name = 'system'; value = 'http://127.0.0.1:8136' },
            @{ name = 'npm'; value = '' },
            @{ name = 'pip'; value = $null }
        )
        $r.consistent | Should -BeTrue
    }
    It '协议前缀差异不算冲突' {
        $r = Get-ProxyChainSummary -Layers @(
            @{ name = 'system'; value = '127.0.0.1:8136' },
            @{ name = 'git'; value = 'http://127.0.0.1:8136/' }
        )
        $r.consistent | Should -BeTrue
    }
}

Describe '负载探针' {
    It '加载签名表并返回结构' {
        $r = Get-WorkloadsProbe -TimeBudgetSeconds 30
        $r.id | Should -Be 'probe.workloads'
        $r.ok | Should -BeTrue
        $r.data.catalogSize | Should -BeGreaterThan 0
        @($r.data.workloads).Count | Should -Be $r.data.catalogSize
    }
    It '已安装项有 roots，未安装项标记 installed=false' {
        $r = Get-WorkloadsProbe -TimeBudgetSeconds 30
        foreach ($w in $r.data.workloads) {
            if ($w.installed) { @($w.roots.Keys).Count | Should -BeGreaterThan 0 }
            else { $w.verdict | Should -Be 'none' }
        }
    }
    It 'review 类型单独累计，不计入 cache/data' {
        $r = Get-WorkloadsProbe -TimeBudgetSeconds 30
        foreach ($w in $r.data.workloads) {
            $sum = 0L
            foreach ($i in $w.items) { if ($i.kind -eq 'review' -and $i.size -gt 0) { $sum += $i.size } }
            $w.reviewBytes | Should -Be $sum
        }
    }

    It '缓存与数据分别累计' {
        $r = Get-WorkloadsProbe -TimeBudgetSeconds 30
        foreach ($w in $r.data.workloads) {
            $cacheSum = 0L
            foreach ($i in $w.items) { if ($i.kind -eq 'cache' -and $i.size -gt 0) { $cacheSum += $i.size } }
            $w.cacheBytes | Should -Be $cacheSum
        }
    }
}