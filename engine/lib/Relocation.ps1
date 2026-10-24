#Requires -Version 5.1
<#
.SYNOPSIS
  迁移策略层：决定「缓存/数据该不该搬、搬到哪、用什么方法搬」。
.DESCRIPTION
  核心不是「一律搬出 C 盘」，而是三条判据：
    1) 数据在已知文件夹里（文档/下载/图片……）-> 只移动该文件夹一次，不为每个软件单独设
    2) 热数据（实时渲染、IDE 索引、流媒体缓存）-> 留在最快的盘；它本来就会自动清理，搬到机械盘只会更卡
    3) 冷数据（游戏、虚拟机、离线素材）-> 搬到剩余空间最大的盘，容量优先于速度
  另外：安全软件、驱动、系统组件永不搬。
#>

$script:MEDIA_RANK = @{ 'NVMe' = 4; 'SSD' = 3; 'Unspecified' = 2; 'HDD' = 1; 'Unknown' = 0 }

function Get-RelocationVolumeProfile {
    <#  盘符 -> @{ media; bus; totalGB; freeGB; rank }  #>
    $map = @{}
    try {
        $disks = @{}
        foreach ($d in (Get-PhysicalDisk -ErrorAction Stop)) { $disks[[int]$d.DeviceId] = $d }
        foreach ($p in (Get-Partition -ErrorAction Stop | Where-Object { $_.DriveLetter })) {
            $letter = ([string]$p.DriveLetter) + ':'
            $disk = $disks[[int]$p.DiskNumber]
            $media = 'Unknown'
            $bus = 'Unknown'
            if ($disk) {
                $media = [string]$disk.MediaType
                $bus = [string]$disk.BusType
                if ($media -eq 'SSD' -and $bus -eq 'NVMe') { $media = 'NVMe' }
            }
            $vol = Get-Volume -DriveLetter $p.DriveLetter -ErrorAction SilentlyContinue
            $rank = 0
            if ($script:MEDIA_RANK.ContainsKey($media)) { $rank = $script:MEDIA_RANK[$media] }
            $map[$letter] = @{
                media = $media
                bus = $bus
                rank = $rank
                totalGB = if ($vol) { [math]::Round($vol.Size / 1GB, 0) } else { 0 }
                freeGB = if ($vol) { [math]::Round($vol.SizeRemaining / 1GB, 0) } else { 0 }
            }
        }
    } catch { }
    return $map
}

function Get-RelocationKnownFolders {
    <#  已知文件夹当前路径（中文系统也适用，用 Environment 而非注册表）  #>
    $folders = [ordered]@{}
    $map = @{
        Desktop   = 'Desktop'
        Documents = 'MyDocuments'
        Downloads = 'UserProfile'
        Pictures  = 'MyPictures'
        Videos    = 'MyVideos'
        Music     = 'MyMusic'
    }
    foreach ($k in $map.Keys) {
        $p = ''
        try { $p = [Environment]::GetFolderPath($map[$k]) } catch { }
        if ($k -eq 'Downloads') {
            $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name '{374DE290-123F-4565-9164-39C4925E467B}' -ErrorAction SilentlyContinue).'{374DE290-123F-4565-9164-39C4925E467B}'
            if ($v) { $p = [Environment]::ExpandEnvironmentVariables([string]$v) }
        }
        $folders[$k] = $p
    }
    return $folders
}

function Get-KnownFolderRoots {
    <#  把已知文件夹暴露成模板变量 kfDocuments / kfDesktop / kfDownloads ...  #>
    $kf = Get-RelocationKnownFolders
    $roots = @{}
    foreach ($k in $kf.Keys) {
        $v = [string]$kf[$k]
        if ($v) { $roots['kf' + $k] = $v }
    }
    return $roots
}

function Get-PathDrive {
    param([string]$Path = '')
    if ($Path -match '^([A-Za-z]):') { return ($Matches[1].ToUpper() + ':') }
    return ''
}

function Test-PathUnderKnownFolder {
    <#  返回命中的已知文件夹名，否则空串。  #>
    param([string]$Path = '', $KnownFolders = $null)
    if (-not $Path -or -not $KnownFolders) { return '' }
    $p = $Path.TrimEnd('\')
    foreach ($k in $KnownFolders.Keys) {
        $root = [string]$KnownFolders[$k]
        if (-not $root) { continue }
        $r = $root.TrimEnd('\')
        if ($p.Equals($r, [StringComparison]::OrdinalIgnoreCase)) { return $k }
        if ($p.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)) { return $k }
    }
    return ''
}

function Get-FastestVolume {
    param($Volumes = @{}, [string]$Exclude = '')
    $best = $null
    foreach ($k in $Volumes.Keys) {
        if ($k -eq $Exclude) { continue }
        $v = $Volumes[$k]
        if (-not $best) { $best = @{ drive = $k; vol = $v }; continue }
        if ([int]$v.rank -gt [int]$best.vol.rank) { $best = @{ drive = $k; vol = $v } }
        elseif ([int]$v.rank -eq [int]$best.vol.rank -and [int]$v.freeGB -gt [int]$best.vol.freeGB) { $best = @{ drive = $k; vol = $v } }
    }
    return $best
}

function Get-LargestFreeVolume {
    param($Volumes = @{}, [string]$Exclude = '', [int]$MinFreeGB = 50)
    $best = $null
    foreach ($k in $Volumes.Keys) {
        if ($k -eq $Exclude) { continue }
        $v = $Volumes[$k]
        if ([int]$v.freeGB -lt $MinFreeGB) { continue }
        if (-not $best) { $best = @{ drive = $k; vol = $v }; continue }
        if ([int]$v.freeGB -gt [int]$best.vol.freeGB) { $best = @{ drive = $k; vol = $v } }
    }
    if (-not $best) {
        foreach ($k in $Volumes.Keys) {
            if ($k -eq $Exclude) { continue }
            $v = $Volumes[$k]
            if (-not $best -or [int]$v.freeGB -gt [int]$best.vol.freeGB) { $best = @{ drive = $k; vol = $v } }
        }
    }
    return $best
}

function Get-AppDeclaredPaths {
    <#
      读取「软件自己记录的保存路径」，这是判断「先装后搬」还是「先搬后装」的硬证据。
      返回 @{ 'workload.xxx' = @{ source; value } }
    #>
    $out = @{}
    # 微信 3.x
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Tencent\WeChat' -Name FileSavePath -ErrorAction Stop).FileSavePath
        if ($v) { $out['workload.wechat'] = @{ source = 'HKCU\Software\Tencent\WeChat\FileSavePath'; value = [string]$v } }
    } catch { }
    # Steam 库配置
    try {
        $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath
        if ($sp) {
            $vdf = Join-Path ($sp.Replace('/', '\')) 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                $paths = @(Get-Content -LiteralPath $vdf -ErrorAction SilentlyContinue | ForEach-Object { if ($_ -match '"path"\s+"([^"]+)"') { $Matches[1].Replace('\\', '\') } })
                if ($paths.Count -gt 0) { $out['workload.steam'] = @{ source = 'libraryfolders.vdf'; value = ($paths -join '; ') } }
            }
        }
    } catch { }
    # JetBrains：idea.properties 里的 system 路径
    try {
        $jb = Join-Path $env:APPDATA 'JetBrains'
        if (Test-Path -LiteralPath $jb) {
            $props = @(Get-ChildItem -LiteralPath $jb -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'idea.properties' } | Where-Object { Test-Path -LiteralPath $_ })
            foreach ($f in $props) {
                $line = Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*idea\.system\.path\s*=' } | Select-Object -First 1
                if ($line) { $out['workload.jetbrains'] = @{ source = $f; value = ($line -split '=', 2)[1].Trim() }; break }
            }
        }
    } catch { }
    return $out
}

function Get-RelocationChecklist {
    <#
      强制决策清单：引擎只把问题摆出来，答案必须由 Agent 结合上下文填写。
      这三条对应最常见的三种误判。
    #>
    return @(
        '它是否落在已知文件夹（文档/下载/桌面/图片/视频/音乐）之下？若是，应移动该文件夹一次，而不是给单个软件设路径。',
        '它是热数据还是冷数据？热数据（实时渲染缓存、IDE 索引、流媒体缓存）应留在最快的盘，它本来就会自动清理；冷数据（游戏/虚拟机/书库/聊天记录）才考虑搬到容量盘。',
        '该软件是否已经记录了自己的绝对路径（先装后搬）？若是，移动后必须同步修改软件内的保存路径，否则会指回旧路径或在原处重建空目录。'
    )
}

function Get-RelocationFacts {
    <#
      纯事实层：不判断、不建议，只把可客观测量的信息摊开。
      返回数组，元素：@{ workload; label; path; kind; size; drive; media; exists; knownFolder; declaredPath }
    #>
    param(
        [array]$Workloads = @(),
        $Volumes = @{},
        $KnownFolders = [ordered]@{},
        $DeclaredPaths = @{}
    )
    $facts = @()
    foreach ($wl in $Workloads) {
        if (-not $wl.installed) { continue }
        $declared = $null
        if ($DeclaredPaths -and $DeclaredPaths.ContainsKey([string]$wl.id)) { $declared = $DeclaredPaths[[string]$wl.id] }
        foreach ($it in @($wl.items)) {
            if (-not $it.path) { continue }
            $drive = Get-PathDrive -Path $it.path
            $vol = $null
            if ($drive -and $Volumes.ContainsKey($drive)) { $vol = $Volumes[$drive] }
            $facts += [pscustomobject]@{
                workload = [string]$wl.name
                label = [string]$it.label
                path = [string]$it.path
                kind = [string]$it.kind
                size = [int64]$it.size
                drive = $drive
                media = if ($vol) { [string]$vol.media } else { 'Unknown' }
                freeGB = if ($vol) { [int]$vol.freeGB } else { 0 }
                exists = (Test-Path -LiteralPath $it.path)
                knownFolder = (Test-PathUnderKnownFolder -Path $it.path -KnownFolders $KnownFolders)
                declaredPath = if ($declared) { $declared.value } else { '' }
                declaredSource = if ($declared) { $declared.source } else { '' }
            }
        }
    }
    return $facts
}

function Get-RelocationAdvice {
    <#
      纯函数（可单测）：对每个 workload 的每个条目给出迁移建议。
      政策（policy）：keep-fast / move-cold / never / ask
      返回数组，元素：
        @{ workload; label; path; kind; policy; action; target; reason; warning }
      action: keep | move | known-folder | ask | skip
    #>
    param(
        [array]$Workloads = @(),
        $Volumes = @{},
        $KnownFolders = [ordered]@{},
        $DeclaredPaths = @{},
        [string]$SystemDrive = 'C:'
    )
    $advices = @()
    $fastest = Get-FastestVolume -Volumes $Volumes -Exclude ''
    $largest = Get-LargestFreeVolume -Volumes $Volumes -Exclude $SystemDrive

    foreach ($wl in $Workloads) {
        if (-not $wl.installed) { continue }
        foreach ($it in @($wl.items)) {
            if (-not $it.path) { continue }
            $policy = [string]$it.policy
            if (-not $policy) {
                $policy = switch ([string]$it.kind) {
                    'cache'  { 'keep-fast' }
                    'data'   { 'move-cold' }
                    'config' { 'never' }
                    default  { 'ask' }
                }
            }
            $drive = Get-PathDrive -Path $it.path
            $vol = $null
            if ($drive -and $Volumes.ContainsKey($drive)) { $vol = $Volumes[$drive] }
            $media = if ($vol) { [string]$vol.media } else { 'Unknown' }
            $base = @{
                workload = [string]$wl.name
                label = [string]$it.label
                path = [string]$it.path
                kind = [string]$it.kind
                policy = $policy
                policySource = 'default-hint'
                drive = $drive
                media = $media
                size = [int64]$it.size
            }

            switch ($policy) {
                'never' {
                    $base.action = 'skip'; $base.target = ''; $base.reason = '系统/安全/配置类，不迁移'; $base.warning = ''
                }
                'ask' {
                    $base.action = 'ask'; $base.target = ''; $base.reason = '内容混合，需人工确认后才能决定'; $base.warning = ''
                }
                'keep-fast' {
                    if ($media -in @('NVMe', 'SSD')) {
                        $base.action = 'keep'; $base.target = $drive
                        $base.reason = ('热数据且已在 ' + $media + '，会自动清理，搬走反而变慢')
                        $base.warning = ''
                    } elseif ($media -eq 'HDD') {
                        $base.action = 'move'
                        $base.target = if ($fastest) { $fastest.drive } else { '' }
                        $base.reason = '热数据落在机械盘上，读写延迟会明显拖慢'
                        $base.warning = '搬到固态后请确认程序设置里已同步修改'
                    } else {
                        $base.action = 'keep'; $base.target = $drive; $base.reason = '无法判定磁盘介质，保持现状'; $base.warning = ''
                    }
                }
                default {
                    $kf = Test-PathUnderKnownFolder -Path $it.path -KnownFolders $KnownFolders
                    if ($kf) {
                        $root = [string]$KnownFolders[$kf]
                        $rootDrive = Get-PathDrive -Path $root
                        if ($rootDrive -and $rootDrive -ne $SystemDrive) {
                            $base.action = 'keep'; $base.target = $rootDrive
                            $base.reason = ('属于已知文件夹「' + $kf + '」，已在 ' + $rootDrive + '，无需为单个软件设置')
                            $base.warning = ''
                        } else {
                            $declared = $null
                            if ($DeclaredPaths -and $DeclaredPaths.ContainsKey([string]$wl.id)) { $declared = $DeclaredPaths[[string]$wl.id] }
                            $exists = Test-Path -LiteralPath $it.path
                            if ($exists) {
                                $base.action = 'known-folder-then-app'
                                $base.phase = 'post-install'
                                $base.target = if ($largest) { $largest.drive } else { '' }
                                $base.reason = ('属于已知文件夹「' + $kf + '」且该软件**已经在用**这个目录；移动文件夹后必须同步改软件内的保存路径')
                                $base.warning = '只改文件夹不改软件设置 -> 软件会指回旧路径，或在原处重建一个空目录'
                                if ($declared) { $base.declaredPath = $declared }
                            } else {
                                $base.action = 'known-folder'
                                $base.phase = 'pre-install'
                                $base.target = if ($largest) { $largest.drive } else { '' }
                                $base.reason = ('属于已知文件夹「' + $kf + '」且软件尚未在此写入数据；先移动文件夹，之后安装会自动落到新位置')
                                $base.warning = ''
                            }
                        }
                    } else {
                        if ($drive -eq $SystemDrive -and $largest) {
                            $base.action = 'move'; $base.target = $largest.drive
                            $base.reason = ('冷数据在系统盘，' + $largest.drive + ' 剩余 ' + $largest.vol.freeGB + ' GB 更宽裕')
                            $base.warning = ''
                        } else {
                            $base.action = 'keep'; $base.target = $drive
                            $base.reason = '已不在系统盘'; $base.warning = ''
                        }
                    }
                }
            }
            $advices += [pscustomobject]$base
        }
    }
    return $advices
}

function Format-RelocationFacts {
    param([array]$Facts = @())
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('| 软件 | 条目 | 路径 | 介质 | 存在 | 已知文件夹 | 软件声明路径 | 类型 | 体积 MB |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|---:|')
    foreach ($f in $Facts) {
        $sizeMb = if ($f.size -gt 0) { [math]::Round($f.size / 1MB, 0) } else { 0 }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |' -f $f.workload, $f.label, ($f.path -replace '\|', '/'), $f.media, $f.exists, $(if ($f.knownFolder) { $f.knownFolder } else { '-' }), $(if ($f.declaredPath) { $f.declaredPath } else { '-' }), $f.kind, $sizeMb))
    }
    return $sb.ToString().TrimEnd()
}

function Format-RelocationReport {
    param([array]$Advices = @(), $Volumes = @{})
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('磁盘概况')
    foreach ($k in ($Volumes.Keys | Sort-Object)) {
        $v = $Volumes[$k]
        [void]$sb.AppendLine(('  {0}  {1,-5} 共 {2} GB 可用 {3} GB' -f $k, $v.media, $v.totalGB, $v.freeGB))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 软件 | 条目 | 位置 | 介质 | 建议 | 说明 |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|')
    $actionText = @{ keep = '保持'; move = '迁移'; 'known-folder' = '移动文件夹(先搬后装)'; 'known-folder-then-app' = '移动文件夹+改软件设置(先装后搬)'; ask = '需确认'; skip = '不迁移' }
    foreach ($a in $Advices) {
        $adv = $actionText[[string]$a.action]
        if ($a.target -and $a.action -in @('move', 'known-folder')) { $adv = $adv + ' -> ' + $a.target }
        $note = $a.reason
        if ($a.warning) { $note = $note + '（注意：' + $a.warning + '）' }
        if ($a.declaredPath) { $note = $note + '〔软件当前记录：' + $a.declaredPath.value + '〕' }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $a.workload, $a.label, $a.drive, $a.media, $adv, ($note -replace '\|', '/')))
    }
    return $sb.ToString().TrimEnd()
}