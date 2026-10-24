#Requires -Version 5.1
<#
.SYNOPSIS
  邮件客户端域探针（只读）：Outlook 版本、配置文件、数据文件体积、加载项状态。
.NOTES
  「邮件收不到」的常见根因依次是：加载项冲突、OST/PST 过大、配置文件损坏、账户设置错误。
  本域只读取证；连通性测试（ping / Test-NetConnection / Telnet 端口）由宿主 Agent 显式执行，不进引擎。
#>

function Get-OstSizeVerdict {
    <#  纯函数：数据文件体积判定。  #>
    param([int64]$Bytes = 0)
    if ($Bytes -le 0) { return 'empty' }
    $gb = $Bytes / 1GB
    if ($gb -ge 50) { return 'oversize' }
    if ($gb -ge 25) { return 'large' }
    if ($gb -ge 5) { return 'normal' }
    return 'small'
}

function Get-AddinLoadVerdict {
    <#  纯函数：Outlook 加载项 LoadBehavior 语义映射。  #>
    param([int]$LoadBehavior = 0)
    switch ($LoadBehavior) {
        0  { return 'disabled' }
        1  { return 'loaded-no-command' }
        2  { return 'not-loaded' }
        3  { return 'loaded' }
        8  { return 'loaded-on-demand' }
        9  { return 'on-demand' }
        16 { return 'load-first-time' }
        default { return ('unknown(' + $LoadBehavior + ')') }
    }
}

function Get-OutlookProfileInfo {
    foreach ($v in @('16.0', '15.0', '14.0')) {
        $base = 'HKCU:\Software\Microsoft\Office\' + $v + '\Outlook\Profiles'
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $names = @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName })
        $def = (Get-ItemProperty ('HKCU:\Software\Microsoft\Office\' + $v + '\Outlook') -Name DefaultProfile -ErrorAction SilentlyContinue).DefaultProfile
        return @{ version = $v; profiles = $names; defaultProfile = [string]$def }
    }
    return @{ version = ''; profiles = @(); defaultProfile = '' }
}

function Get-MailDataFiles {
    <#  枚举 %LOCALAPPDATA%\Microsoft\Outlook 下的 ost/pst。  #>
    $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
    $files = @()
    if (Test-Path -LiteralPath $dir) {
        foreach ($f in (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.ost', '.pst') })) {
            $files += @{
                name = $f.Name
                path = $f.FullName
                size = [int64]$f.Length
                lastWrite = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                verdict = (Get-OstSizeVerdict -Bytes ([int64]$f.Length))
            }
        }
    }
    return @{ dir = $dir; files = $files }
}

function Get-OutlookAddins {
    $found = @()
    $roots = @(
        'HKCU:\Software\Microsoft\Office\Outlook\Addins',
        'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins'
    )
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($k in (Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            $lb = 0
            if ($p -and $null -ne $p.LoadBehavior) { $lb = [int]$p.LoadBehavior }
            $found += @{
                name = $k.PSChildName
                loadBehavior = $lb
                state = (Get-AddinLoadVerdict -LoadBehavior $lb)
                source = $r
            }
        }
    }
    return $found
}

function Get-MailClientsProbe {
    param()
    $profile = Get-OutlookProfileInfo
    $dataFiles = Get-MailDataFiles
    $addins = Get-OutlookAddins
    $outlookExe = ''
    foreach ($c in @(
        (Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16\OUTLOOK.EXE'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\root\Office16\OUTLOOK.EXE'),
        (Join-Path $env:ProgramFiles 'Microsoft Office\Office16\OUTLOOK.EXE')
    )) {
        if ($c -and (Test-Path -LiteralPath $c)) { $outlookExe = $c; break }
    }
    $newOutlook = ''
    foreach ($c in @((Join-Path $env:LOCALAPPDATA 'Microsoft\Olk\olk.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Olk\olk.exe'))) {
        if ($c -and (Test-Path -LiteralPath $c)) { $newOutlook = $c; break }
    }
    $totalBytes = 0L
    foreach ($f in $dataFiles.files) { $totalBytes += [int64]$f.size }
    $problemAddins = @($addins | Where-Object { $_.state -in @('not-loaded', 'disabled') })
    return @{
        id = 'probe.mail-clients'
        ok = $true
        data = @{
            outlookInstalled = [bool]$outlookExe
            outlookExe = $outlookExe
            newOutlookExe = $newOutlook
            officeVersion = $profile.version
            profiles = @($profile.profiles)
            defaultProfile = $profile.defaultProfile
            dataDir = $dataFiles.dir
            dataFiles = @($dataFiles.files)
            dataFileCount = @($dataFiles.files).Count
            dataTotalBytes = $totalBytes
            addinCount = @($addins).Count
            problemAddinCount = $problemAddins.Count
            addins = @($addins)
            note = '只读取证；端口与连通性测试请用 Test-NetConnection 显式执行'
        }
        candidates = @()
    }
}