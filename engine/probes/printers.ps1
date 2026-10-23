#Requires -Version 5.1
<#
.SYNOPSIS
  打印机域探针（只读）。
#>

function Get-PrinterWorkOfflineVerdict {
    <#  纯函数：根据打印机状态字段给出人话裁决。  #>
    param([string]$Status = '', [bool]$WorkOffline = $false, [string]$JobStatus = '')
    if ($WorkOffline) { return '脱机（WorkOffline），系统认为打印机不可用' }
    $s = ([string]$Status).ToLowerInvariant()
    if ($s -match 'jam') { return '卡纸' }
    if ($s -match 'no ?paper|paper ?out|out of paper') { return '缺纸' }
    if ($s -match 'toner|ink') { return '耗材不足' }
    if ($s -match 'paused') { return '已暂停' }
    if ($s -match 'offline') { return '脱机' }
    if ($s -match 'error') { return '打印机报错' }
    if ($JobStatus -and $JobStatus -match 'error') { return '队列中有错误任务' }
    return '正常'
}

function Get-PrintersProbe {
    param()
    $printers = @()
    try {
        foreach ($p in (Get-Printer -ErrorAction Stop)) {
            $printers += @{
                name = [string]$p.Name
                driver = [string]$p.DriverName
                port = [string]$p.PortName
                status = [string]$p.PrinterStatus
                workOffline = [bool]$p.WorkOffline
                shared = [bool]$p.Shared
                verdict = (Get-PrinterWorkOfflineVerdict -Status ([string]$p.PrinterStatus) -WorkOffline ([bool]$p.WorkOffline))
            }
        }
    } catch { }
    $defaultName = ''
    try {
        $d = Get-CimInstance Win32_Printer -ErrorAction Stop | Where-Object { $_.Default -eq $true } | Select-Object -First 1
        if ($d) { $defaultName = [string]$d.Name }
    } catch { }
    $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    $jobs = @()
    try {
        $jobs = @(Get-Printer | Get-PrintJob -ErrorAction SilentlyContinue | ForEach-Object {
            @{ printer = [string]$_.PrinterName; id = $_.Id; document = [string]$_.DocumentName; status = [string]$_.JobStatus }
        })
    } catch { }
    $problem = @($printers | Where-Object { $_.verdict -ne '正常' })
    return @{
        id = 'probe.printers'
        ok = $true
        data = @{
            count = $printers.Count
            printers = $printers
            defaultPrinter = $defaultName
            spoolerStatus = if ($spooler) { $spooler.Status.ToString() } else { 'NotFound' }
            queuedJobs = $jobs
            problemCount = $problem.Count
            problems = $problem
        }
        candidates = @()
    }
}