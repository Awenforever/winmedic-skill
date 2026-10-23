#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\probes\security.ps1')
}

Describe '病毒库天数计算' {
    It '按日期差计算' {
        $now = Get-Date '2026-10-23'
        Get-SignatureAgeDays -LastUpdated '2026-10-20' -Now $now | Should -Be 3
    }
    It '未知返回 -1' {
        Get-SignatureAgeDays -LastUpdated $null | Should -Be -1
    }
    It '当天为 0' {
        $now = Get-Date '2026-10-23'
        Get-SignatureAgeDays -LastUpdated '2026-10-23' -Now $now | Should -Be 0
    }
}

Describe '安全裁决' {
    It '全部正常返回 ok' {
        $r = Get-SecurityVerdict -RealTimeEnabled $true -SignatureAgeDays 1 -FirewallEnabled $true -BitLockerProtected $true
        $r.verdict | Should -Be 'ok'
        @($r.issues).Count | Should -Be 0
    }
    It '单一问题返回 attention' {
        $r = Get-SecurityVerdict -RealTimeEnabled $true -SignatureAgeDays 30 -FirewallEnabled $true -BitLockerProtected $true
        $r.verdict | Should -Be 'attention'
        ($r.issues -join '|') | Should -Match '病毒库'
    }
    It '多个问题返回 risk' {
        $r = Get-SecurityVerdict -RealTimeEnabled $false -SignatureAgeDays 30 -FirewallEnabled $false -BitLockerProtected $true
        $r.verdict | Should -Be 'risk'
        @($r.issues).Count | Should -BeGreaterThan 1
    }
    It '未知项不误判为不安全' {
        $r = Get-SecurityVerdict -RealTimeEnabled $null -SignatureAgeDays -1 -FirewallEnabled $null -BitLockerProtected $null
        $r.verdict | Should -Be 'ok'
    }
}

Describe 'BitLocker 版本适配' {
    It '专业版视为支持' {
        Test-BitLockerSupported -Edition 'Microsoft Windows 11 Pro' | Should -BeTrue
    }
    It '中文家庭版视为不支持' {
        Test-BitLockerSupported -Edition 'Microsoft Windows 11 家庭版 中文版' | Should -BeFalse
    }
    It '英文 Home 视为不支持' {
        Test-BitLockerSupported -Edition 'Windows 11 Home' | Should -BeFalse
    }
    It '未知版本时按支持处理（不误报）' {
        Test-BitLockerSupported -Edition '' | Should -BeTrue
    }
}

Describe '安全探针' {
    It '总体探针返回裁决与四类细节' {
        $r = Get-SecurityPostureProbe
        $r.id | Should -Be 'probe.security-posture'
        $r.data.verdict | Should -BeIn @('ok', 'attention', 'risk')
        $r.data.ContainsKey('defender') | Should -BeTrue
        $r.data.ContainsKey('firewall') | Should -BeTrue
        $r.data.ContainsKey('bitlocker') | Should -BeTrue
        $r.data.ContainsKey('hardening') | Should -BeTrue
    }
    It '防火墙探针返回配置文件列表' {
        $r = Get-FirewallProbe
        $r.id | Should -Be 'probe.firewall'
        $r.data.ContainsKey('profiles') | Should -BeTrue
    }
}