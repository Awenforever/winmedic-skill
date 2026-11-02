#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\probes\network.ps1')
}

Describe '代理字符串解析' {
    It 'host:port' {
        $e = @(Convert-ProxyEndpoint -Text '127.0.0.1:7890')
        $e.Count | Should -Be 1
        $e[0].host | Should -Be '127.0.0.1'
        $e[0].port | Should -Be 7890
    }
    It '分协议写法' {
        $e = @(Convert-ProxyEndpoint -Text 'http=127.0.0.1:7890;https=127.0.0.1:7891')
        $e.Count | Should -Be 2
        ($e | Where-Object { $_.port -eq 7891 }).scheme | Should -Be 'https'
    }
    It '带 scheme 和路径' {
        $e = @(Convert-ProxyEndpoint -Text 'http://127.0.0.1:8080/')
        $e[0].host | Should -Be '127.0.0.1'
        $e[0].port | Should -Be 8080
    }
    It 'IPv6 回环' {
        $e = @(Convert-ProxyEndpoint -Text 'socks5://[::1]:1080')
        $e[0].host | Should -Be '::1'
        $e[0].port | Should -Be 1080
    }
    It '空值返回空数组' {
        @(Convert-ProxyEndpoint -Text '').Count | Should -Be 0
    }
}

Describe '回环端口存活' {
    It '关闭的端口返回 false' {
        Test-LoopbackTcpPort -HostName '127.0.0.1' -Port 1 -TimeoutMs 300 | Should -BeFalse
    }
    It '监听中的端口返回 true' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
            Test-LoopbackTcpPort -HostName '127.0.0.1' -Port $port -TimeoutMs 1000 | Should -BeTrue
        } finally { $listener.Stop() }
    }
}