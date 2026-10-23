#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
    . (Join-Path $repo 'engine\lib\Journal.ps1')
    . (Join-Path $repo 'engine\lib\Action.ps1')
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
}
AfterAll {
    Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue
}

Describe '隔离区移动' {
    It '目标不存在时判定为已消失而不是错误' {
        $item = [pscustomobject]@{ id = 'R1'; target = (Join-Path $TestDrive 'not-exists-dir') }
        $action = [pscustomobject]@{ kind = 'quarantine' }
        $r = Invoke-CdriveAction -Item $item -Action $action -RunId 'TESTRUN'
        $r.ok | Should -BeTrue
        $r.alreadyAbsent | Should -BeTrue
        $r.mode | Should -Be 'absent'
    }
    It '跨卷移动被拒绝' {
        $item = [pscustomobject]@{ id = 'R2'; target = 'Z:\some\path' }
        $action = [pscustomobject]@{ kind = 'quarantine' }
        $r = Invoke-CdriveAction -Item $item -Action $action -RunId 'TESTRUN'
        $r.ok | Should -BeFalse
        $r.error | Should -Match '跨卷'
    }
}

Describe '命令动作' {
    It '成功命令返回 ok 与输出哈希' {
        $item = [pscustomobject]@{ id = 'R3'; target = 'noop' }
        $action = [pscustomobject]@{ kind = 'command'; command = 'cmd /c exit 0' }
        $r = Invoke-CdriveAction -Item $item -Action $action -RunId 'TESTRUN'
        $r.ok | Should -BeTrue
        $r.outputSha256.Length | Should -Be 64
    }
    It '失败命令返回非零退出码' {
        $item = [pscustomobject]@{ id = 'R4'; target = 'noop' }
        $action = [pscustomobject]@{ kind = 'command'; command = 'cmd /c exit 3' }
        $r = Invoke-CdriveAction -Item $item -Action $action -RunId 'TESTRUN'
        $r.ok | Should -BeFalse
        $r.exitCode | Should -Be 3
    }
}