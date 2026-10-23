#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\probes\updates.ps1')
}

Describe '设备错误码翻译' {
    It '0 表示正常' {
        Get-DeviceErrorMeaning -Code 0 | Should -Be '正常'
    }
    It '28 表示驱动未安装' {
        Get-DeviceErrorMeaning -Code 28 | Should -Be '驱动未安装'
    }
    It '43 表示设备被停止' {
        Get-DeviceErrorMeaning -Code 43 | Should -Match '停止'
    }
    It '未知码给出可读提示而不是空' {
        Get-DeviceErrorMeaning -Code 999 | Should -Match '未知错误码'
    }
}

Describe '待重启判定' {
    It '返回结构化结果' {
        $r = Get-PendingRebootState
        $r.ContainsKey('pending') | Should -BeTrue
        $r.ContainsKey('reasons') | Should -BeTrue
    }
    It 'pending 与 reasons 一致' {
        $r = Get-PendingRebootState
        if (@($r.reasons).Count -gt 0) { $r.pending | Should -BeTrue } else { $r.pending | Should -BeFalse }
    }
}

Describe '更新探针' {
    It '返回服务状态与待重启信息' {
        $r = Get-WindowsUpdateProbe
        $r.id | Should -Be 'probe.windows-update'
        $r.ok | Should -BeTrue
        $r.data.ContainsKey('services') | Should -BeTrue
        $r.data.ContainsKey('pendingReboot') | Should -BeTrue
    }
}

Describe '驱动探针' {
    It '返回问题设备与显卡驱动' {
        $r = Get-DriverProbe
        $r.id | Should -Be 'probe.drivers'
        $r.ok | Should -BeTrue
        $r.data.ContainsKey('problemDevices') | Should -BeTrue
        $r.data.ContainsKey('gpuDrivers') | Should -BeTrue
    }
    It '问题设备条目都带中文解释' {
        $r = Get-DriverProbe
        foreach ($d in $r.data.problemDevices) {
            $d.meaning | Should -Not -BeNullOrEmpty
        }
    }
}