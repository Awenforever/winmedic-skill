#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\probes\netlink.ps1')
    # 指向一个必然连不上的代理：保证「走采样分支」，不依赖本机是否配置代理
    $script:deadProxy = 'http://127.0.0.1:1'
}

Describe 'net-link 探针（离线可判定）' {
    It '对不可达目标也返回结构化结果，不抛错' {
        $r = Invoke-NetLinkCheck -Hosts @('localhost') -Proxy $script:deadProxy -Samples 1 -Bytes 1 -TimeoutSec 2
        $r.PSObject.Properties.Name | Should -Contain 'stallRate'
        $r.PSObject.Properties.Name | Should -Contain 'proxyOk'
        @($r.hosts).Count | Should -Be 1
        @($r.samples).Count | Should -Be 1
    }
    It '停滞率始终落在 0..1' {
        $r = Invoke-NetLinkCheck -Hosts @('localhost') -Proxy $script:deadProxy -Samples 1 -Bytes 1 -TimeoutSec 2
        [double]$r.stallRate | Should -BeGreaterOrEqual 0
        [double]$r.stallRate | Should -BeLessOrEqual 1
    }
    It 'Get-NetLinkProbe 无论成败都返回 probe.net-link' {
        $p = Get-NetLinkProbe -Proxy $script:deadProxy -Samples 1 -Bytes 1 -TimeoutSec 2
        $p.id | Should -Be 'probe.net-link'
        $null -ne $p.data | Should -BeTrue
    }
}

Describe 'engine 完整性清单' {
    It '清单存在且列出的文件都在' {
        $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $m = Join-Path $repo 'engine\MANIFEST.txt'
        Test-Path $m | Should -BeTrue
        $missing = @()
        foreach ($rel in (Get-Content $m -Encoding UTF8)) {
            if (-not $rel.Trim()) { continue }
            $full = Join-Path (Join-Path $repo 'engine') ($rel.Trim() -replace '/', '\')
            if (-not (Test-Path $full)) { $missing += $rel }
        }
        $missing.Count | Should -Be 0 -Because ('缺失: ' + ($missing -join ','))
    }
}