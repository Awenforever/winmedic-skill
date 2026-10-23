#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\probes\recovery.ps1')
}

Describe '还原点探针' {
    It '返回计数与说明' {
        $r = Get-RestorePointProbe
        $r.id | Should -Be 'probe.restore-points'
        $r.data.ContainsKey('count') | Should -BeTrue
        $r.data.ContainsKey('points') | Should -BeTrue
    }
    It '无权限时给出错误文本而不是抛异常' {
        $r = Get-RestorePointProbe
        $r.data.ContainsKey('error') | Should -BeTrue
    }
}

Describe '卷影副本探针' {
    It '返回结构' {
        $r = Get-ShadowCopyProbe
        $r.id | Should -Be 'probe.shadow-copies'
        $r.data.ContainsKey('count') | Should -BeTrue
    }
}

Describe 'WinRE 探针' {
    It '不可用时也不抛异常' {
        $r = Get-WinREProbe
        $r.id | Should -Be 'probe.winre'
        $r.data.ContainsKey('available') | Should -BeTrue
    }
}

Describe '恢复能力总评' {
    It '给出 ready/weak/poor 之一' {
        $r = Get-RecoveryReadinessProbe
        $r.id | Should -Be 'probe.recovery-readiness'
        $r.data.level | Should -BeIn @('ready', 'weak', 'poor')
    }
    It '风险项与等级一致' {
        $r = Get-RecoveryReadinessProbe
        $n = @($r.data.risks).Count
        if ($n -eq 0) { $r.data.level | Should -Be 'ready' }
        elseif ($n -eq 1) { $r.data.level | Should -Be 'weak' }
        else { $r.data.level | Should -Be 'poor' }
    }
}