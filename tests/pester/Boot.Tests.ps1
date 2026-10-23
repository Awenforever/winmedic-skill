#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Scan.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
    . (Join-Path $repo 'engine\probes\boot.ps1')
}

Describe '启动项分类器' {
    It '安全软件归为 security' {
        Get-StartupRiskCategory -Name 'Huorong' -Command 'C:\Program Files\Huorong\wsctrl.exe' | Should -Be 'security'
        Get-StartupRiskCategory -Name 'Windows Defender' | Should -Be 'security'
    }
    It '输入法归为 input' {
        Get-StartupRiskCategory -Name 'SogouImeBroker' | Should -Be 'input'
    }
    It '显卡与外设归为 driver' {
        Get-StartupRiskCategory -Name 'Realtek HD Audio' | Should -Be 'driver'
        Get-StartupRiskCategory -Name 'LogiOptionsPlus' | Should -Be 'driver'
    }
    It '更新器归为 updater' {
        Get-StartupRiskCategory -Name 'TencentUpdater' | Should -Be 'updater'
    }
    It '网盘归为 sync' {
        Get-StartupRiskCategory -Name 'OneDrive' | Should -Be 'sync'
    }
    It 'Windows 安全中心托盘归为 security' {
        Get-StartupRiskCategory -Name 'SecurityHealth' | Should -Be 'security'
    }
    It '系统自带清理任务归为 system' {
        Get-StartupRiskCategory -Name 'msedge_cleanup_ABC' | Should -Be 'system'
        Get-StartupRiskCategory -Name 'Delete Cached Update Binary' | Should -Be 'system'
    }
    It 'Adobe 与虚拟机托盘归为 vendor' {
        Get-StartupRiskCategory -Name 'Adobe CCXProcess' | Should -Be 'vendor'
        Get-StartupRiskCategory -Name 'vmware-tray.exe' | Should -Be 'vendor'
    }
    It '未知程序不瞎归类' {
        Get-StartupRiskCategory -Name 'Zxqw123' -Command 'C:\Temp\a.exe' | Should -Be 'unknown'
    }
}

Describe '启动项探针' {
    It '返回结构化结果且不抛异常' {
        $r = Get-StartupItemsProbe
        $r.id | Should -Be 'probe.startup-items'
        $r.ok | Should -BeTrue
        $r.data.ContainsKey('items') | Should -BeTrue
    }
    It '每项都带建议动作' {
        $r = Get-StartupItemsProbe
        foreach ($i in $r.data.items) {
            $i.advice | Should -BeIn @('keep', 'optional-disable', 'investigate')
        }
    }
}

Describe '性能基线探针' {
    It '给出裁决字段' {
        $r = Get-PerfBaselineProbe
        $r.data.ContainsKey('verdict') | Should -BeTrue
        $r.data.verdict | Should -BeIn @('ok', 'memory-pressure', 'commit-near-limit', 'disk-pressure', 'unknown')
    }
}

Describe '启动耗时探针' {
    It '事件日志不可读时也不抛异常' {
        $r = Get-BootTimeProbe
        $r.id | Should -Be 'probe.boot-time'
        $r.data.ContainsKey('available') | Should -BeTrue
    }
}