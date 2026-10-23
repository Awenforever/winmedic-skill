#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
    $script:Repo = $repo
}

Describe '红线判定' {
    It '命中 WinSxS 内部路径' {
        Test-RedlinePath -Path 'C:\Windows\WinSxS\Temp\abc' | Should -BeTrue
    }
    It '命中 Windows\Installer' {
        Test-RedlinePath -Path 'C:\Windows\Installer\foo.msi' | Should -BeTrue
    }
    It '命中聊天记录目录' {
        Test-RedlinePath -Path 'C:\Users\u\Documents\WeChat Files\x' | Should -BeTrue
        Test-RedlinePath -Path 'D:\xwechat_files\msg' | Should -BeTrue
    }
    It '不误伤普通缓存路径' {
        Test-RedlinePath -Path 'C:\Windows\Panther' | Should -BeFalse
        Test-RedlinePath -Path 'C:\Users\u\AppData\Local\Microsoft\Edge\User Data\Default\Cache' | Should -BeFalse
    }
    It '给出原因文本' {
        (Get-RedlineReason -Path 'C:\Windows\System32\drivers') | Should -Match 'system32'
    }
}

Describe '前置检查' {
    It 'admin 检查返回结构化结果' {
        $r = Test-Precondition -Spec 'admin'
        $r.Name | Should -Be 'admin'
        $r.ContainsKey('Ok') | Should -BeTrue
        $r.ContainsKey('Detail') | Should -BeTrue
    }
    It '未知前置返回失败而不是抛异常' {
        $r = Test-Precondition -Spec 'no-such-check:1'
        $r.Ok | Should -BeFalse
        $r.Detail | Should -Match '未知'
    }
    It '提交余量检查返回结构化结果' {
        $r = Test-Precondition -Spec 'commit-headroom:5'
        $r.Name | Should -Be 'commit-headroom:5'
        $r.ContainsKey('Ok') | Should -BeTrue
        $r.Detail | Should -Match '提交余量'
    }
    It '过高的余量要求会判失败' {
        $r = Test-Precondition -Spec 'commit-headroom:99'
        $r.Ok | Should -BeFalse
    }
    It '进程检查对不存在进程返回通过' {
        $r = Test-Precondition -Spec 'process-not-running:winmedic_no_such_proc_xyz'
        $r.Ok | Should -BeTrue
    }
}