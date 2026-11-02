#Requires -Version 5.1
<#
.SYNOPSIS
  网络域探针（只读配置，**不发起任何网络请求**）。
.NOTES
  引擎保持「不联网、无遥测」不变量。连通性测试由宿主 Agent 用 ping / Test-NetConnection 显式执行，
  不进引擎，避免扫描或探测行为。
#>

function Test-IsVpnAdapterName {
    <#  纯函数：按适配器名判断是否为虚拟/隧道适配器。  #>
    param([string]$Name = '')
    if (-not $Name) { return $false }
    $n = $Name.ToLowerInvariant()
    return ($n -match 'vpn|tap|tun|wireguard|tailscale|zerotier|clash|wintun|openvpn|anyconnect|forticlient|hamachi|radmin|virtual|vmware|hyper-v|vethernet|loopback')
}

function Get-ProxyConflictSummary {
    <#
      纯函数：比对三处代理配置，检出不一致。
      这正是实测中踩过的坑：git 全局代理停在旧端口 7890，系统代理已是 13499。
    #>
    param([string]$WinInet = '', [string]$WinHttp = '', [string]$EnvHttps = '')
    $norm = { param($v) if (-not $v) { return '' }; ($v -replace 'https?://', '').TrimEnd('/').ToLowerInvariant() }
    $a = & $norm $WinInet
    $b = & $norm $WinHttp
    $c = & $norm $EnvHttps
    $set = @($a, $b, $c | Where-Object { $_ -ne '' }) | Select-Object -Unique
    $consistent = (@($set).Count -le 1)
    $note = ''
    if (-not $consistent) { $note = '多处代理配置不一致，按依赖此配置的程序逐个排查（git 读自己的 http.proxy）' }
    elseif (@($set).Count -eq 0) { $note = '未配置代理' }
    else { $note = ('统一为 ' + @($set)[0]) }
    return @{ consistent = $consistent; values = @{ winInet = $WinInet; winHttp = $WinHttp; envHttps = $EnvHttps }; note = $note }
}

function Get-NetworkAdaptersProbe {
    param()
    $adapters = @()
    try {
        foreach ($a in (Get-NetAdapter -ErrorAction Stop)) {
            $adapters += @{
                name = $a.Name
                description = $a.InterfaceDescription
                status = [string]$a.Status
                linkSpeed = [string]$a.LinkSpeed
                virtual = (Test-IsVpnAdapterName -Name ($a.Name + ' ' + $a.InterfaceDescription))
            }
        }
    } catch { }
    $ips = @()
    try {
        foreach ($c in (Get-NetIPConfiguration -ErrorAction Stop)) {
            $ips += @{
                alias = $c.InterfaceAlias
                ipv4 = @($c.IPv4Address | ForEach-Object { $_.IPAddress })
                gateway = @($c.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
                dns = @($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses })
            }
        }
    } catch { }
    return @{ id = 'probe.network-adapters'; ok = ($adapters.Count -gt 0); data = @{ adapters = $adapters; configs = $ips; upCount = @($adapters | Where-Object { $_.status -eq 'Up' }).Count }; candidates = @() }
}

function Get-DnsConfigProbe {
    param()
    $servers = @()
    try {
        foreach ($d in (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop)) {
            if (@($d.ServerAddresses).Count -gt 0) {
                $servers += @{ alias = $d.InterfaceAlias; servers = @($d.ServerAddresses) }
            }
        }
    } catch { }
    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $hostsEntries = 0
    if (Test-Path -LiteralPath $hostsPath) {
        $lines = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue
        $hostsEntries = @($lines | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }).Count
    }
    $lm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name EnableMulticast -ErrorAction SilentlyContinue
    return @{ id = 'probe.dns-config'; ok = $true; data = @{ servers = $servers; hostsPath = $hostsPath; hostsEntries = $hostsEntries; llmnrDisabled = ($lm -and $lm.EnableMulticast -eq 0) }; candidates = @() }
}

function Convert-ProxyEndpoint {
    <#  纯函数：把代理字符串拆成 host/port 列表。  #>
    param([string]$Text = '')
    $out = @()
    if (-not $Text) { return @() }
    foreach ($part in ($Text -split '[;,]')) {
        $p = ([string]$part).Trim()
        if (-not $p) { continue }
        $scheme = ''
        if ($p -match '^([A-Za-z][A-Za-z0-9+.-]*)=(.+)$') { $scheme = $Matches[1].ToLower(); $p = $Matches[2].Trim() }
        $p = $p -replace '^[A-Za-z][A-Za-z0-9+.-]*://', ''
        $p = $p.TrimEnd('/')
        if ($p -match '^\[([0-9a-fA-F:]+)\]:(\d{1,5})$') {
            $out += [pscustomobject]@{ scheme = $scheme; host = $Matches[1]; port = [int]$Matches[2] }
        } elseif ($p -match '^([^:\[\]]+):(\d{1,5})$') {
            $out += [pscustomobject]@{ scheme = $scheme; host = $Matches[1]; port = [int]$Matches[2] }
        }
    }
    return @($out)
}

function Test-LoopbackTcpPort {
    param([string]$HostName = '127.0.0.1', [int]$Port = 0, [int]$TimeoutMs = 500)
    try {
        $c = New-Object Net.Sockets.TcpClient
        $iar = $c.BeginConnect($HostName, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs)
        if ($ok) { $c.EndConnect($iar) }
        $c.Close()
        return [bool]$ok
    } catch { return $false }
}

function Get-ProxyLiveness {
    param([string[]]$Texts = @())
    $eps = @()
    foreach ($t in @($Texts)) { $eps += @(Convert-ProxyEndpoint -Text $t) }
    $eps = @($eps | Sort-Object host, port -Unique)
    $rows = @()
    foreach ($e in $eps) {
        $loop = @('127.0.0.1', 'localhost', '::1') -contains $e.host
        $alive = $null
        if ($loop) { $alive = Test-LoopbackTcpPort -HostName $e.host -Port $e.port }
        $rows += [pscustomobject]@{ scheme = $e.scheme; host = $e.host; port = $e.port; loopback = $loop; alive = $alive }
    }
    return @($rows)
}

function Get-ProxyConfigProbe {
    param()
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    $winInet = ''
    if ($ie -and $ie.ProxyEnable -eq 1 -and $ie.ProxyServer) { $winInet = [string]$ie.ProxyServer }
    $winHttp = ''
    try { $winHttp = ((netsh winhttp show proxy 2>$null) | Out-String) } catch { }
    $winHttpValue = ''
    $m = [regex]::Match($winHttp, '代理服务器\s*:\s*(\S+)|Proxy Server\(s\)\s*:\s*(\S+)')
    if ($m.Success) { $winHttpValue = if ($m.Groups[1].Value) { $m.Groups[1].Value } else { $m.Groups[2].Value } }
    $envHttps = [string]$env:HTTPS_PROXY
    if (-not $envHttps) { $envHttps = [string]$env:https_proxy }
    $summary = Get-ProxyConflictSummary -WinInet $winInet -WinHttp $winHttpValue -EnvHttps $envHttps
    $live = Get-ProxyLiveness -Texts @($winInet, $envHttps)
    $dead = @($live | Where-Object { $_.alive -eq $false })
    return @{ id = 'probe.proxy-config'; ok = $true; data = @{ winInet = $winInet; winHttp = $winHttpValue; envHttps = $envHttps; summary = $summary; bypass = if ($ie) { [string]$ie.ProxyOverride } else { '' }; endpoints = @($live); deadCount = $dead.Count; dead = @($dead | ForEach-Object { $_.host + ':' + $_.port }) }; candidates = @() }
}

function Get-VpnAdaptersProbe {
    param()
    $found = @()
    try {
        foreach ($a in (Get-NetAdapter -ErrorAction Stop)) {
            $blob = $a.Name + ' ' + $a.InterfaceDescription
            if (Test-IsVpnAdapterName -Name $blob) {
                $found += @{ name = $a.Name; description = $a.InterfaceDescription; status = [string]$a.Status }
            }
        }
    } catch { }
    return @{ id = 'probe.vpn-adapters'; ok = $true; data = @{ count = $found.Count; adapters = $found }; candidates = @() }
}