#Requires -Version 5.1
<#
.SYNOPSIS
  音频域探针：端点状态、每应用路由、音频/蓝牙服务、HFP 节点、虚拟声卡。
.DESCRIPTION
  只读。默认设备需要交互式会话，SSH/session 0 下取不到，探针如实标注。
#>

function Convert-AudioDeviceState {
    param([int64]$Value)
    $core = [int]($Value -band 0xF)
    $label = switch ($core) {
        1 { 'ACTIVE' }
        2 { 'DISABLED' }
        4 { 'NOTPRESENT' }
        8 { 'UNPLUGGED' }
        default { 'UNKNOWN' }
    }
    return [pscustomobject]@{ value = $Value; core = $core; label = $label }
}

function Get-AudioEndpointList {
    param([ValidateSet('Render', 'Capture')][string]$Kind = 'Render')
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\' + $Kind
    $list = @()
    foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
        $stateValue = 0
        try { $stateValue = [int64](Get-ItemProperty -LiteralPath $k.PSPath -Name DeviceState -ErrorAction Stop).DeviceState } catch { }
        $st = Convert-AudioDeviceState -Value $stateValue
        $propsPath = $k.PSPath + '\Properties'
        $props = Get-ItemProperty -LiteralPath $propsPath -ErrorAction SilentlyContinue
        $name = ''
        $deviceId = ''
        if ($props) {
            if ($props.PSObject.Properties.Name -contains '{a45c254e-df1c-4efd-8020-67d146a850e0},2') { $name = [string]$props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2' }
            if ($props.PSObject.Properties.Name -contains '{b3f8fa53-0004-438e-9003-51a46e139bfc},2') { $deviceId = [string]$props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},2' }
        }
        $kindOf = 'other'
        if ($deviceId -match '(?i)bthenum') { $kindOf = 'bluetooth' }
        elseif ($deviceId -match '(?i)^\{[^}]+\}\.USB') { $kindOf = 'usb' }
        elseif ($deviceId -match '(?i)hdaudio') { $kindOf = 'hdaudio' }
        $vid = ''; $btPid = ''
        if ($deviceId -match '(?i)vid&([0-9a-f]+)_pid&([0-9a-f]+)') { $vid = $Matches[1].ToLower(); $btPid = $Matches[2].ToLower() }
        $exclusiveAllowed = 1
        if ($props) {
            $ex = $null
            if ($props.PSObject.Properties.Name -contains '{b3f8fa53-0004-438e-9003-51a46e139bfc},3') { $ex = $props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},3' }
            if ($null -ne $ex) {
                try { if (@($ex).Count -ge 3 -and [int]@($ex)[2] -eq 0) { $exclusiveAllowed = 0 } } catch { }
            }
        }
        $list += [pscustomobject]@{
            guid = [string]$k.PSChildName; name = $name; stateValue = $stateValue; state = $st.label;
            kind = $kindOf; vid = $vid; pid = $btPid; deviceId = $deviceId; exclusiveAllowed = $exclusiveAllowed
        }
    }
    return @($list)
}

function Get-AudioBtNameMap {
    $map = @{}
    foreach ($d in @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)) {
        if (-not $d.FriendlyName) { continue }
        if ($d.FriendlyName -match 'Avrcp|Enumerator|RFCOMM|Adapter|Generic|LE ') { continue }
        if ($d.InstanceId -match '(?i)vid&([0-9a-f]+)_pid&([0-9a-f]+)') {
            $key = $Matches[1].ToLower() + '/' + $Matches[2].ToLower()
            if (-not $map.ContainsKey($key)) { $map[$key] = [string]$d.FriendlyName }
        }
    }
    return $map
}

function Get-AudioEndpointsProbe {
    param()
    $render = Get-AudioEndpointList -Kind Render
    $capture = Get-AudioEndpointList -Kind Capture
    $active = @($render | Where-Object { $_.state -eq 'ACTIVE' })
    $btActive = @($render | Where-Object { $_.kind -eq 'bluetooth' -and $_.state -eq 'ACTIVE' })
    $hfp = @(Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Hands-Free' })
    $hfpNotOk = @($hfp | Where-Object { $_.Status -ne 'OK' })
    $virtual = @(Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Virtual|VB-Audio|Voicemeeter|Steam Streaming' } | ForEach-Object { [string]$_.FriendlyName })
    $exclusiveAllowed = @($render | Where-Object { $_.exclusiveAllowed -eq 1 }).Count
    return @{
        id = 'probe.audio-endpoints'; ok = $true;
        data = @{
            render = @($render); capture = @($capture)
            counts = @{ render = $render.Count; capture = $capture.Count; active = $active.Count; bluetoothActive = $btActive.Count; hfp = $hfp.Count; hfpNotOk = $hfpNotOk.Count; exclusiveAllowed = $exclusiveAllowed }
            activeNames = @($active | ForEach-Object { $_.name })
            btActiveNames = @($btActive | ForEach-Object { $_.name })
            hfpDevices = @($hfp | ForEach-Object { @{ name = [string]$_.FriendlyName; status = [string]$_.Status } })
            virtualDevices = @($virtual)
            defaultDeviceNote = '默认设备需交互式会话，远程/服务会话下无法获取'
        };
        candidates = @()
    }
}

function Get-AudioAppRoutingProbe {
    param()
    $store = 'HKCU:\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore'
    $render = Get-AudioEndpointList -Kind Render
    $activeBt = @($render | Where-Object { $_.kind -eq 'bluetooth' -and $_.state -eq 'ACTIVE' })
    $activeKeys = @($activeBt | ForEach-Object { $_.vid + '/' + $_.pid })
    $nameMap = Get-AudioBtNameMap
    $entries = @()
    foreach ($k in @(Get-ChildItem -LiteralPath $store -ErrorAction SilentlyContinue)) {
        $vals = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        if (-not $vals) { continue }
        foreach ($p in @($vals.PSObject.Properties)) {
            if ($p.Name -match '^PS') { continue }
            $raw = [string]$p.Value
            if ($raw -notmatch '\|') { continue }
            $parts = $raw.Split([char]124, 2)
            $dev = $parts[0]; $tail = $parts[1]
            $kind = 'other'; $vid = ''; $btPid = ''
            if ($dev -match '(?i)bthenum') {
                $kind = 'bluetooth'
                if ($dev -match '(?i)vid&([0-9a-f]+)_pid&([0-9a-f]+)') { $vid = $Matches[1].ToLower(); $btPid = $Matches[2].ToLower() }
            }
            $app = ''
            if ($tail -match '(\\Device\\HarddiskVolume\d+\\[^%]+)') { $app = $Matches[1] }
            elseif ($tail -match '([A-Za-z]:\\[^%]+)') { $app = $Matches[1] }
            $stale = $false
            $orphan = $false
            $paired = $false
            $deviceName = ''
            if ($kind -eq 'bluetooth') {
                $key = $vid + '/' + $btPid
                $paired = $nameMap.ContainsKey($key)
                if ($paired) { $deviceName = [string]$nameMap[$key] }
                # stale = 设备仍配对/存在，但没有活跃端点（应用被钉在断开的设备上）
                # orphan = 设备已不在系统里（历史残留，通常无害）
                $stale = $paired -and (-not ($activeKeys -contains $key))
                $orphan = -not $paired
            }
            $entries += [pscustomobject]@{
                key = [string]$k.PSChildName; kind = $kind; vid = $vid; pid = $btPid; deviceName = $deviceName;
                app = $app; paired = $paired; stale = $stale; orphan = $orphan
            }
        }
    }
    $staleEntries = @($entries | Where-Object { $_.stale })
    $orphanEntries = @($entries | Where-Object { $_.orphan })
    return @{
        id = 'probe.audio-app-routing'; ok = $true;
        data = @{
            total = $entries.Count
            staleCount = $staleEntries.Count
            orphanCount = $orphanEntries.Count
            entries = @($entries)
            stale = @($staleEntries)
            activeBluetooth = @($activeBt | ForEach-Object { $_.name })
        };
        candidates = @()
    }
}

function Get-AudioServicesProbe {
    param()
    $names = @('Audiosrv', 'AudioEndpointBuilder', 'bthserv', 'BTAGService', 'BthAvctpSvc')
    $svc = @()
    foreach ($n in $names) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        $svc += [pscustomobject]@{ name = $n; status = if ($s) { [string]$s.Status } else { 'Missing' } }
    }
    $allRunning = -not (@($svc | Where-Object { $_.status -ne 'Running' }).Count -gt 0)
    $audiodg = @(Get-Process -Name audiodg -ErrorAction SilentlyContinue)
    return @{
        id = 'probe.audio-services'; ok = $true;
        data = @{
            services = @($svc)
            allRunning = $allRunning
            audiodgRunning = ($audiodg.Count -gt 0)
            audiodgPid = if ($audiodg.Count -gt 0) { $audiodg[0].Id } else { 0 }
        };
        candidates = @()
    }
}
