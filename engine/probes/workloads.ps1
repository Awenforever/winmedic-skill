#Requires -Version 5.1
<#
.SYNOPSIS
  软件负载域（只读）：按签名表测量具体软件的缓存/数据体积，并检查代理链路一致性。
.NOTES
  设计：不为每个软件写代码。`catalog/workloads.json` 描述「怎么定位 + 有哪些目录」，
  本探针负责解析签名、测量、给出可执行的清理建议。加新软件 = 加一条签名。
#>

function Get-WorkloadCatalog {
    param([string]$CatalogPath)
    if (-not $CatalogPath) {
        $root = $script:WinMedicRoot
        if (-not $root) { $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
        $CatalogPath = Join-Path $root 'catalog\workloads.json'
    }
    if (-not (Test-Path -LiteralPath $CatalogPath)) { return @() }
    $raw = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($raw.workloads)
}

function Expand-WorkloadTemplate {
    <#  纯函数：把 {root} 占位符替换成实际路径；未知占位符返回 $null。  #>
    param([string]$Template = '', [hashtable]$Roots = @{})
    if (-not $Template) { return $null }
    $out = $Template
    $ms = [regex]::Matches($Template, '\{([A-Za-z0-9_]+)\}')
    foreach ($m in $ms) {
        $key = $m.Groups[1].Value
        if (-not $Roots.ContainsKey($key) -or -not $Roots[$key]) { return $null }
        $out = $out.Replace($m.Value, [string]$Roots[$key])
    }
    $out = [Environment]::ExpandEnvironmentVariables($out)
    return $out
}

function Resolve-WorkloadRoots {
    param([Parameter(Mandatory)]$Signature)
    $roots = @{}
    if (-not $Signature.detect) { return $roots }
    foreach ($d in @($Signature.detect)) {
        $type = [string]$d.type
        $as = [string]$d.as
        if (-not $as) { continue }
        if ($roots.ContainsKey($as) -and $roots[$as]) { continue }
        switch ($type) {
            'registry' {
                $v = $null
                try { $v = (Get-ItemProperty -LiteralPath ([string]$d.path) -Name ([string]$d.name) -ErrorAction Stop).($d.name) } catch { }
                if ($v) { $roots[$as] = ([string]$v).Replace('/', '\') }
            }
            'command' {
                $c = Get-Command ([string]$d.name) -ErrorAction SilentlyContinue
                if ($c -and $c.Source) {
                    $p = [string]$c.Source
                    $trim = 0
                    if ($d.trim) { $trim = [int]$d.trim }
                    for ($i = 0; $i -lt $trim; $i++) { $p = Split-Path -Parent $p }
                    if ($p) { $roots[$as] = $p }
                }
            }
            'path' {
                $p = [Environment]::ExpandEnvironmentVariables([string]$d.path)
                if (Test-Path -LiteralPath $p) { $roots[$as] = $p }
            }
        }
    }
    return $roots
}

function Get-WorkloadSize {
    <#  目录用 robocopy 列表模式快速求和；文件直接取长度。  #>
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return -1 }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer) { return [int64]$item.Length }
    $o = robocopy $Path NULL /l /s /njh /bytes /nfl /ndl /r:0 /w:0 2>$null | Out-String
    $m = [regex]::Match($o, '(?:Bytes|字节)\s*:\s*([0-9]+)')
    if ($m.Success) { return [int64]$m.Groups[1].Value }
    $s = Get-PathSize -Path $Path
    return [int64]$s.Size
}

function Get-WorkloadVerdict {
    <#  纯函数：按缓存合计给结论。  #>
    param([int64]$CacheBytes = 0, [int64]$DataBytes = 0)
    $gb = $CacheBytes / 1GB
    if ($gb -ge 10) { return 'heavy' }
    if ($gb -ge 2) { return 'notable' }
    if ($gb -gt 0) { return 'small' }
    return 'none'
}

function Get-WorkloadsProbe {
    param(
        [int]$TimeBudgetSeconds = 60,
        [string]$CatalogPath
    )
    $catalog = Get-WorkloadCatalog -CatalogPath $CatalogPath
    $results = @()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $truncated = $false

    foreach ($sig in $catalog) {
        if ($sw.Elapsed.TotalSeconds -gt $TimeBudgetSeconds) { $truncated = $true; break }
        $roots = Resolve-WorkloadRoots -Signature $sig
        $installed = ($roots.Count -gt 0)
        $items = @()
        $cacheBytes = 0L
        $dataBytes = 0L
        if ($installed) {
            foreach ($m in @($sig.measure)) {
                $tpl = [string]$m.path
                $resolved = Expand-WorkloadTemplate -Template $tpl -Roots $roots
                if (-not $resolved) { continue }
                $kind = [string]$m.kind
                $skipSize = $false
                if ($m.skipSize) { $skipSize = [bool]$m.skipSize }
                $paths = @()
                if ($resolved.Contains('*')) {
                    $paths = @(Get-Item -Path $resolved -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
                } elseif (Test-Path -LiteralPath $resolved) {
                    $paths = @($resolved)
                }
                foreach ($p in $paths) {
                    $size = -1
                    if (-not $skipSize) { $size = Get-WorkloadSize -Path $p }
                    if (-not $skipSize -and $size -le 0) { continue }
                    $items += [pscustomobject]@{ label = [string]$m.label; kind = $kind; path = $p; size = $size; skipped = $skipSize }
                    if ($size -gt 0) {
                        if ($kind -eq 'cache') { $cacheBytes += $size }
                        elseif ($kind -eq 'data') { $dataBytes += $size }
                    }
                }
            }
        }
        $results += [pscustomobject]@{
            id = [string]$sig.id
            name = [string]$sig.name
            playbook = [string]$sig.playbook
            installed = $installed
            roots = $roots
            items = @($items)
            cacheBytes = $cacheBytes
            dataBytes = $dataBytes
            verdict = (Get-WorkloadVerdict -CacheBytes $cacheBytes -DataBytes $dataBytes)
            cautions = @($sig.cautions)
        }
    }
    $sw.Stop()

    $installedOnes = @($results | Where-Object { $_.installed })
    $totalCache = 0L
    foreach ($r in $installedOnes) { $totalCache += [int64]$r.cacheBytes }
    return @{
        id = 'probe.workloads'
        ok = $true
        data = @{
            catalogSize = @($catalog).Count
            installedCount = $installedOnes.Count
            totalCacheBytes = $totalCache
            seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            truncated = $truncated
            workloads = @($results)
        }
        candidates = @()
    }
}

function Get-ProxyChainSummary {
    <#
      纯函数：比对系统代理 / WinHTTP / git / npm / pip 五处配置。
      Layers: 有序数组，元素 @{ name; value }
      isTestOnly：空值不算冲突（表示该层没配置）。
    #>
    param([array]$Layers = @())
    $norm = {
        param($v)
        if (-not $v) { return '' }
        $s = [string]$v
        $s = $s -replace '^(https?|socks5?)://', ''
        $s = $s.TrimEnd('/')
        return $s.ToLowerInvariant()
    }
    $pairs = @()
    foreach ($l in $Layers) { $pairs += @{ name = [string]$l.name; raw = [string]$l.value; norm = (& $norm ([string]$l.value)) } }
    $nonEmpty = @($pairs | Where-Object { $_.norm })
    $distinct = @($nonEmpty | ForEach-Object { $_.norm } | Select-Object -Unique)
    $consistent = ($distinct.Count -le 1)
    $conflicts = @()
    if (-not $consistent) {
        $conflicts = @($nonEmpty | ForEach-Object { $_.name + '=' + $_.raw })
    }
    return @{ consistent = $consistent; layers = $pairs; conflicts = $conflicts; distinctCount = $distinct.Count }
}

function Get-ProxyChainProbe {
    param()
    $layers = @()
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    $winInet = ''
    if ($ie -and $ie.ProxyEnable -eq 1 -and $ie.ProxyServer) { $winInet = 'http://' + [string]$ie.ProxyServer }
    $layers += @{ name = 'system(WinINET)'; value = $winInet }

    $winHttp = ''
    try {
        $o = (netsh winhttp show proxy 2>$null | Out-String)
        $m = [regex]::Match($o, '(?:代理服务器|Proxy Server\(s\))\s*:\s*(\S+)')
        if ($m.Success) { $winHttp = $m.Groups[1].Value }
    } catch { }
    $layers += @{ name = 'WinHTTP'; value = $winHttp }

    $gitProxy = ''
    try { $gitProxy = [string](& git config --global --get http.proxy 2>$null) } catch { }
    $layers += @{ name = 'git'; value = $gitProxy }

    $npmProxy = ''
    $npmrc = Join-Path $env:USERPROFILE '.npmrc'
    if (Test-Path -LiteralPath $npmrc) {
        $line = Get-Content -LiteralPath $npmrc -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*proxy\s*=' } | Select-Object -First 1
        if ($line) { $npmProxy = ($line -split '=', 2)[1].Trim() }
    }
    $layers += @{ name = 'npm'; value = $npmProxy }

    $pipProxy = ''
    foreach ($ini in @((Join-Path $env:APPDATA 'pip\pip.ini'), (Join-Path $env:USERPROFILE 'pip\pip.ini'))) {
        if (-not (Test-Path -LiteralPath $ini)) { continue }
        $line = Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*proxy\s*=' } | Select-Object -First 1
        if ($line) { $pipProxy = ($line -split '=', 2)[1].Trim(); break }
    }
    $layers += @{ name = 'pip'; value = $pipProxy }

    $summary = Get-ProxyChainSummary -Layers $layers

    $clients = @()
    $patterns = 'clash|verge|v2ray|xray|sing-box|wireguard|openvpn|anyconnect|tailscale|zerotier|加速器|极连|隐云|Panabit|小黑盒|Shadowrocket'
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($e in (Get-ItemProperty $keys -ErrorAction SilentlyContinue)) {
        if (-not $e.DisplayName) { continue }
        if ([string]$e.DisplayName -notmatch $patterns) { continue }
        $clients += [pscustomobject]@{ name = [string]$e.DisplayName; version = [string]$e.DisplayVersion; location = [string]$e.InstallLocation }
    }

    return @{
        id = 'probe.proxy-chain'
        ok = $true
        data = @{
            consistent = $summary.consistent
            distinctCount = $summary.distinctCount
            layers = @($summary.layers)
            conflicts = @($summary.conflicts)
            clientCount = @($clients).Count
            clients = @($clients)
            note = '代理客户端卸载/切换端口后，各层配置常不同步；这是「关掉代理反而全断」的常见原因'
        }
        candidates = @()
    }
}