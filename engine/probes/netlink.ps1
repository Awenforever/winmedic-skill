function Invoke-NetLinkCheck {
    <#
      只读链路体检（可独立运行，不依赖引擎其它文件）。
      输出：DNS、直连 TCP、代理可达、长连接停滞率。
      不做任何写操作。
    #>
    param(
        [string[]]$Hosts = @('api.openai.com', 'chatgpt.com'),
        [string]$Proxy = '',
        [int]$Samples = 3,
        [int64]$Bytes = 5000000,
        [int]$TimeoutSec = 10,
        [string]$StallUrl = 'https://speed.cloudflare.com/__down?bytes=5000000'
    )

    $proxyUrl = $Proxy
    if (-not $proxyUrl) {
        $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($ie -and $ie.ProxyEnable -eq 1 -and $ie.ProxyServer) { $proxyUrl = 'http://' + [string]$ie.ProxyServer }
    }
    if (-not $proxyUrl -and $env:HTTPS_PROXY) { $proxyUrl = [string]$env:HTTPS_PROXY }

    $hostResults = @()
    foreach ($h in $Hosts) {
        $dnsOk = $false
        $ips = @()
        try {
            $ips = @([System.Net.Dns]::GetHostAddresses($h) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.IPAddressToString })
            $dnsOk = ($ips.Count -gt 0)
        } catch { }

        $tcpOk = $false
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $ar = $c.BeginConnect($h, 443, $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(3000)) { $c.EndConnect($ar); $tcpOk = $true }
            $c.Close()
        } catch { }

        $hostResults += [pscustomobject]@{ host = $h; dnsOk = $dnsOk; ips = @($ips); directTcpOk = $tcpOk }
    }

    $proxyOk = $false
    $proxyStatus = 0
    $stallRate = 0.0
    $sampleResults = @()

    if ($proxyUrl) {
        try {
            Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
            $handler = New-Object System.Net.Http.HttpClientHandler
            $handler.Proxy = New-Object System.Net.WebProxy($proxyUrl)
            $handler.UseProxy = $true
            $client = New-Object System.Net.Http.HttpClient($handler)
            $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

            try {
                $resp = $client.GetAsync('https://api.openai.com/v1/models').Result
                $proxyStatus = [int]$resp.StatusCode
                $proxyOk = $true
                $resp.Dispose()
            } catch {
                if ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
                    $proxyStatus = [int]$_.Exception.InnerException.Response.StatusCode
                    $proxyOk = $true
                }
            }

            $complete = 0
            $stalled = 0
            for ($i = 1; $i -le $Samples; $i++) {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $got = 0L
                $state = 'error'
                try {
                    $r2 = $client.GetAsync($StallUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
                    $stream = $r2.Content.ReadAsStreamAsync().Result
                    $buf = New-Object byte[] 65536
                    while ($got -lt $Bytes -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
                        $n = $stream.Read($buf, 0, $buf.Length)
                        if ($n -le 0) { break }
                        $got += $n
                    }
                    $stream.Dispose()
                    $r2.Dispose()
                    if ($got -ge $Bytes) { $state = 'complete' } elseif ($got -gt 0) { $state = 'stalled' } else { $state = 'empty' }
                } catch {
                    $state = 'error'
                }
                $sw.Stop()
                if ($state -eq 'complete') { $complete++ } elseif ($state -eq 'stalled' -or $state -eq 'empty') { $stalled++ }
                $sampleResults += [pscustomobject]@{ index = $i; state = $state; bytes = $got; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 3) }
            }
            $valid = $complete + $stalled
            if ($valid -gt 0) { $stallRate = [math]::Round($stalled / $valid, 3) }
            $client.Dispose()
        } catch { }
    }

    return [pscustomobject]@{
        hosts        = @($hostResults)
        proxy        = $proxyUrl
        proxyOk      = $proxyOk
        proxyStatus  = $proxyStatus
        samples      = @($sampleResults)
        complete     = @($sampleResults | Where-Object { $_.state -eq 'complete' }).Count
        stalledCount = @($sampleResults | Where-Object { $_.state -ne 'complete' }).Count
        stallRate    = $stallRate
        checkedAt    = (Get-Date).ToString('o')
    }
}

function Get-NetLinkProbe {
    param([int]$Samples = 3, [int64]$Bytes = 5000000, [int]$TimeoutSec = 10, [string]$Proxy = '')
    try {
        $r = Invoke-NetLinkCheck -Samples $Samples -Bytes $Bytes -TimeoutSec $TimeoutSec -Proxy $Proxy
        $directOk = @($r.hosts | Where-Object { $_.directTcpOk }).Count
        $dnsOk = @($r.hosts | Where-Object { $_.dnsOk }).Count
        return @{
            id = 'probe.net-link'
            ok = $true
            data = @{
                hosts = @($r.hosts); proxy = $r.proxy; proxyOk = $r.proxyOk; proxyStatus = $r.proxyStatus
                samples = @($r.samples); stallRate = $r.stallRate; complete = $r.complete; stalledCount = $r.stalledCount
                dnsOkHosts = $dnsOk; directOkHosts = $directOk; totalHosts = @($r.hosts).Count
            }
            candidates = @()
        }
    } catch {
        return @{ id = 'probe.net-link'; ok = $false; data = @{ error = $_.Exception.Message }; candidates = @() }
    }
}
