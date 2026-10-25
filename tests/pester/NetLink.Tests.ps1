#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\probes\netlink.ps1')
}

Describe 'net-link 探针' {
    It '返回 DNS/直连/代理/采样四类事实' {
        $r = Get-NetLinkProbe -Samples 1 -Bytes 200000 -TimeoutSec 8
        $r.id | Should -Be 'probe.net-link'
        @($r.data.hosts).Count | Should -BeGreaterThan 0
        @($r.data.Keys) | Should -Contain 'proxyOk'
        @($r.data.Keys) | Should -Contain 'stallRate'
        @($r.data.samples).Count | Should -Be 1
    }
    It '停滞率在 0..1 之间' {
        $r = Get-NetLinkProbe -Samples 1 -Bytes 200000 -TimeoutSec 8
        [double]$r.data.stallRate | Should -BeGreaterOrEqual 0
        [double]$r.data.stallRate | Should -BeLessOrEqual 1
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