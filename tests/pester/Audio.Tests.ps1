#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\probes\audio.ps1')
}

Describe '音频设备状态解码' {
    It '1 = ACTIVE' {
        (Convert-AudioDeviceState -Value 1).label | Should -Be 'ACTIVE'
    }
    It '8 = UNPLUGGED' {
        (Convert-AudioDeviceState -Value 8).label | Should -Be 'UNPLUGGED'
    }
    It '高位标志不影响状态判断' {
        (Convert-AudioDeviceState -Value 268435457).label | Should -Be 'ACTIVE'
        (Convert-AudioDeviceState -Value 553648132).label | Should -Be 'NOTPRESENT'
    }
}

Describe '音频探针' {
    It '端点探针返回结构化数据' {
        $p = Get-AudioEndpointsProbe
        $p.id | Should -Be 'probe.audio-endpoints'
        $p.ok | Should -BeTrue
        $p.data.Keys | Should -Contain 'counts'
        $p.data.counts.Keys | Should -Contain 'bluetoothActive'
        @($p.data.render).Count | Should -BeGreaterOrEqual 0
    }
    It '应用路由探针能识别陈旧条目字段' {
        $p = Get-AudioAppRoutingProbe
        $p.id | Should -Be 'probe.audio-app-routing'
        $p.ok | Should -BeTrue
        $p.data.Keys | Should -Contain 'staleCount'
        [int]$p.data.staleCount | Should -BeGreaterOrEqual 0
        $p.data.Keys | Should -Contain 'orphanCount'
    }
    It '服务探针覆盖 5 个服务' {
        $p = Get-AudioServicesProbe
        $p.id | Should -Be 'probe.audio-services'
        @($p.data.services).Count | Should -Be 5
        $p.data.Keys | Should -Contain 'audiodgRunning'
    }
}

Describe '音频现场快照' {
    It '快照包含默认设备与计数' {
        $s = Get-AudioSnapshot
        $s.PSObject.Properties.Name | Should -Contain 'default'
        $s.counts.Keys | Should -Contain 'bluetoothActive'
        $s.session | Should -Be 'current'
    }
    It '运行器脚本包含引擎路径与快照调用' {
        $txt = New-AudioSnapshotRunner -EngineRoot 'C:\x\winmedic'
        $txt | Should -Match 'probes\\audio\.ps1'
        $txt | Should -Match 'Get-AudioSnapshot'
    }
}