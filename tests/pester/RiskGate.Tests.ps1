#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
    . (Join-Path $repo 'engine\lib\Verify.ps1')
}

Describe '风险门' {
    It '只有 Tier 1/2 时直接放行' {
        $items = @([pscustomobject]@{ tier = 1 }, [pscustomobject]@{ tier = 2 })
        $r = Test-RiskGate -Items $items -RecoveryLevel 'poor'
        $r.allow | Should -BeTrue
        $r.reason | Should -Match '无可回滚风险项'
    }
    It '有 Tier 4 时永远拒绝' {
        $items = @([pscustomobject]@{ tier = 4 })
        $r = Test-RiskGate -Items $items -RecoveryLevel 'ready' -AcceptRisk
        $r.allow | Should -BeFalse
        $r.reason | Should -Match 'Tier 4'
    }
    It 'Tier 3 且恢复能力 ready 时放行' {
        $items = @([pscustomobject]@{ tier = 3 })
        $r = Test-RiskGate -Items $items -RecoveryLevel 'ready'
        $r.allow | Should -BeTrue
    }
    It 'Tier 3 且恢复能力 poor 时拒绝' {
        $items = @([pscustomobject]@{ tier = 3 })
        $r = Test-RiskGate -Items $items -RecoveryLevel 'poor'
        $r.allow | Should -BeFalse
        $r.reason | Should -Match 'accept-risk'
    }
    It '显式接受风险后放行 Tier 3' {
        $items = @([pscustomobject]@{ tier = 3 })
        $r = Test-RiskGate -Items $items -RecoveryLevel 'none' -AcceptRisk
        $r.allow | Should -BeTrue
        $r.reason | Should -Match '显式接受'
    }
    It '恢复能力未知时按不安全处理' {
        $items = @([pscustomobject]@{ tier = 3 })
        (Test-RiskGate -Items $items).allow | Should -BeFalse
    }
}

Describe '还原点验证规则' {
    It '返回结构与说明' {
        $r = Invoke-VerifyRule -Rule ([pscustomobject]@{ kind = 'restore_point_exists' })
        $r.ContainsKey('ok') | Should -BeTrue
        $r.detail | Should -Not -BeNullOrEmpty
    }
}