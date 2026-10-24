#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Journal.ps1')
    . (Join-Path $repo 'engine\lib\Action.ps1')
    . (Join-Path $repo 'engine\lib\SelfTest.ps1')
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
}
AfterAll { Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue }

Describe '沙箱自检' {
    It '全部检查通过' {
        $r = Invoke-WinMedicSelfTest
        $r.ok | Should -BeTrue
        $r.failedCount | Should -Be 0
        @($r.checks).Count | Should -BeGreaterOrEqual 6
        foreach ($c in @($r.checks)) { $c.ok | Should -BeTrue }
    }
    It '默认清理沙箱目录' {
        $r = Invoke-WinMedicSelfTest
        Test-Path -LiteralPath $r.sandbox | Should -BeFalse
    }
    It '-Keep 时保留沙箱' {
        $r = Invoke-WinMedicSelfTest -Keep
        Test-Path -LiteralPath $r.sandbox | Should -BeTrue
        Remove-Item -LiteralPath $r.sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    It '报告明确写出可回滚性结论' {
        $r = Invoke-WinMedicSelfTest
        (Format-SelfTestReport -Result $r) | Should -Match '逐字节一致'
    }
}
