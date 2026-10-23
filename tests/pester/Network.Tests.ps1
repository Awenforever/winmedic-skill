#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\probes\network.ps1')
}

Describe '虚拟网卡识别' {
    It '识别常见 VPN / 隧道网卡' {
        foreach ($n in @('WireGuard Tunnel', 'Tailscale', 'TAP-Windows Adapter V9', 'Clash TUN', 'ZeroTier One')) {
            Test-IsVpnAdapterName -Name $n | Should -BeTrue
        }
    }
    It '识别虚拟化网卡' {
        Test-IsVpnAdapterName -Name 'VMware Network Adapter VMnet8' | Should -BeTrue
        Test-IsVpnAdapterName -Name 'vEthernet (Default Switch)' | Should -BeTrue
    }
    It '物理网卡不误判' {
        Test-IsVpnAdapterName -Name '以太网' | Should -BeFalse
        Test-IsVpnAdapterName -Name 'WLAN' | Should -BeFalse
        Test-IsVpnAdapterName -Name 'Realtek PCIe GbE Family Controller' | Should -BeFalse
    }
    It '空名称返回 false' {
        Test-IsVpnAdapterName -Name '' | Should -BeFalse
    }
}

Describe '代理一致性检查' {
    It '三处一致时判定一致' {
        $r = Get-ProxyConflictSummary -WinInet 'http://127.0.0.1:13499' -WinHttp '127.0.0.1:13499' -EnvHttps 'http://127.0.0.1:13499'
        $r.consistent | Should -BeTrue
    }
    It '端口不一致时判定不一致（实测踩过的坑）' {
        $r = Get-ProxyConflictSummary -WinInet 'http://127.0.0.1:13499' -WinHttp '127.0.0.1:7890'
        $r.consistent | Should -BeFalse
        $r.note | Should -Match '不一致'
    }
    It '全部为空时给出未配置提示' {
        $r = Get-ProxyConflictSummary
        $r.consistent | Should -BeTrue
        $r.note | Should -Match '未配置'
    }
}

Describe '网络探针' {
    It '适配器探针返回结构' {
        $r = Get-NetworkAdaptersProbe
        $r.id | Should -Be 'probe.network-adapters'
        $r.data.ContainsKey('adapters') | Should -BeTrue
    }
    It '代理探针包含一致性摘要' {
        $r = Get-ProxyConfigProbe
        $r.data.summary.ContainsKey('consistent') | Should -BeTrue
    }
    It 'DNS 探针返回 hosts 统计' {
        $r = Get-DnsConfigProbe
        $r.data.ContainsKey('hostsEntries') | Should -BeTrue
    }
    It 'VPN 探针返回计数' {
        $r = Get-VpnAdaptersProbe
        $r.data.ContainsKey('count') | Should -BeTrue
    }
}