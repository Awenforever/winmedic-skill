#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Plan.ps1')
    $script:WinMedicRoot = $repo
    . (Join-Path $repo 'engine\probes\storage.ps1')
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
}
AfterAll { Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue }

Describe '计划来源守卫（纯函数）' {
    It '本地来源允许执行' {
        $p = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'R1'; origin = 'local' }) }
        (Test-PlanOriginAllowed -Plan $p).allowed | Should -BeTrue
    }
    It '无 origin 字段按本地处理（向后兼容）' {
        $p = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'R1' }) }
        (Test-PlanOriginAllowed -Plan $p).allowed | Should -BeTrue
    }
    It '远端来源默认拒绝' {
        $p = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'R1'; origin = 'remote:vm1' }) }
        $r = Test-PlanOriginAllowed -Plan $p
        $r.allowed | Should -BeFalse
        $r.offending | Should -Contain 'remote:vm1'
    }
    It '显式放行对应来源后允许（远端引擎自用）' {
        $p = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'R1'; origin = 'remote:vm1' }) }
        (Test-PlanOriginAllowed -Plan $p -AllowRemoteOrigin 'remote:vm1').allowed | Should -BeTrue
    }
    It '放行值不匹配仍然拒绝' {
        $p = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'R1'; origin = 'remote:vm1' }) }
        (Test-PlanOriginAllowed -Plan $p -AllowRemoteOrigin 'remote:vm2').allowed | Should -BeFalse
    }
    It '混合来源时拒绝' {
        $p = [pscustomobject]@{ items = @(
            [pscustomobject]@{ id = 'R1'; origin = 'local' },
            [pscustomobject]@{ id = 'R2'; origin = 'remote:vm1' }) }
        (Test-PlanOriginAllowed -Plan $p).allowed | Should -BeFalse
    }
}

Describe '数据驱动清理目标' {
    It '按目录表测量并产出候选' {
        $dir = Join-Path $TestDrive 'fake-cache'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $dir 'a.bin'), [byte[]]::new(1048576))
        $catalog = Join-Path $TestDrive 'targets.json'
        $obj = @{ schemaVersion = 1; targets = @(@{
            id = 'clean.test'; actionId = 'storage.test-target'; label = '测试目标';
            paths = @($dir); kind = 'dir'; tier = 2; evidence = 'ev.edge-cache'; requires = @();
            plain = @{ what = 'w'; why = 'y'; consequence = 'c' } }) }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $catalog -Encoding UTF8
        $r = Get-CleanupTargetsProbe -CatalogPath $catalog
        $r.id | Should -Be 'probe.cleanup-targets'
        @($r.data.items).Count | Should -Be 1
        @($r.candidates).Count | Should -Be 1
        $r.candidates[0].actionId | Should -Be 'storage.test-target'
    }
    It '目录不存在时不产出候选' {
        $catalog = Join-Path $TestDrive 'none.json'
        $obj = @{ schemaVersion = 1; targets = @(@{ id = 'clean.none'; actionId = 'x'; label = 'x'; paths = @('C:\no\such\dir\xyz'); kind = 'dir'; tier = 1; evidence = 'ev.wer'; requires = @(); plain = @{ what = 'w'; why = 'y'; consequence = 'c' } }) }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $catalog -Encoding UTF8
        $r = Get-CleanupTargetsProbe -CatalogPath $catalog
        @($r.candidates).Count | Should -Be 0
    }
}