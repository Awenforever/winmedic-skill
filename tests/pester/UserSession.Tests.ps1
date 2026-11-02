#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\UserSession.ps1')
}

Describe '用户会话执行' {
    It '脚本不存在时返回失败而不是抛异常' {
        $out = Join-Path $TestDrive 'nope.json'
        $r = Invoke-InUserSession -ScriptPath (Join-Path $TestDrive 'missing.ps1') -OutFile $out -TimeoutSec 3
        $r.ok | Should -BeFalse
        $r.error | Should -Not -BeNullOrEmpty
    }
}