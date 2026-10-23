#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\probes\printers.ps1')
}

Describe '打印机状态裁决' {
    It 'WorkOffline 优先判定为脱机' {
        Get-PrinterWorkOfflineVerdict -Status 'Normal' -WorkOffline $true | Should -Match '脱机'
    }
    It '识别常见故障' {
        Get-PrinterWorkOfflineVerdict -Status 'Paper Jam' | Should -Match '卡纸'
        Get-PrinterWorkOfflineVerdict -Status 'Paper Out' | Should -Match '缺纸'
        Get-PrinterWorkOfflineVerdict -Status 'Toner Low' | Should -Match '耗材'
        Get-PrinterWorkOfflineVerdict -Status 'Paused' | Should -Match '暂停'
    }
    It '队列错误也算异常' {
        Get-PrinterWorkOfflineVerdict -Status 'Normal' -JobStatus 'Error, Printing' | Should -Match '队列'
    }
    It '正常状态返回正常' {
        Get-PrinterWorkOfflineVerdict -Status 'Normal' -WorkOffline $false | Should -Be '正常'
    }
}

Describe '打印机探针' {
    It '返回结构且不抛异常' {
        $r = Get-PrintersProbe
        $r.id | Should -Be 'probe.printers'
        $r.ok | Should -BeTrue
        $r.data.ContainsKey('printers') | Should -BeTrue
        $r.data.ContainsKey('spoolerStatus') | Should -BeTrue
        $r.data.ContainsKey('queuedJobs') | Should -BeTrue
    }
    It '问题计数与问题列表一致' {
        $r = Get-PrintersProbe
        @($r.data.problems).Count | Should -Be $r.data.problemCount
    }
}