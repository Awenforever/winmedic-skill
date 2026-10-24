#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Relocation.ps1')
    $script:Vols = @{
        'C:' = @{ media = 'NVMe'; rank = 4; totalGB = 240; freeGB = 40 }
        'D:' = @{ media = 'SSD';  rank = 3; totalGB = 900; freeGB = 300 }
        'E:' = @{ media = 'HDD';  rank = 1; totalGB = 1800; freeGB = 800 }
    }
    function New-Wl {
        param([string]$Id, [string]$Name, [string]$Path, [string]$Kind, [string]$Policy = '')
        [pscustomobject]@{ id = $Id; name = $Name; installed = $true; playbook = 'x.md';
            items = @([pscustomobject]@{ label = 'L'; kind = $Kind; policy = $Policy; path = $Path; size = 1GB }) }
    }
}

Describe '已知文件夹的时序判据' {
    It '先搬后装：目录不存在 -> 只移动文件夹' {
        $kf = [ordered]@{ Documents = 'C:\Users\u\Documents' }
        $adv = Get-RelocationAdvice -Workloads @(New-Wl 'w' 'W' 'C:\Users\u\Documents\NoSuchApp' 'data') -Volumes $script:Vols -KnownFolders $kf -SystemDrive 'C:'
        $adv[0].action | Should -Be 'known-folder'
        $adv[0].phase | Should -Be 'pre-install'
    }
    It '先装后搬：目录已存在 -> 移动文件夹且必须改软件设置' {
        $kf = [ordered]@{ Documents = 'C:\Users\u\Documents' }
        $exists = Join-Path $env:TEMP ('kf-' + [guid]::NewGuid().ToString('N').Substring(0,6))
        New-Item -ItemType Directory -Force -Path $exists | Out-Null
        $adv = Get-RelocationAdvice -Workloads @(New-Wl 'w' 'W' $exists 'data') -Volumes $script:Vols -KnownFolders @{ Documents = (Split-Path -Parent $exists) } -SystemDrive 'C:'
        $adv[0].action | Should -Be 'known-folder-then-app'
        $adv[0].phase | Should -Be 'post-install'
        $adv[0].warning | Should -Match '旧路径'
        Remove-Item -LiteralPath $exists -Force -Recurse -ErrorAction SilentlyContinue
    }
    It '已知文件夹已不在系统盘 -> 保持，不为单个软件设置' {
        $kf = [ordered]@{ Documents = 'E:\__VIVE__\Documents' }
        $adv = Get-RelocationAdvice -Workloads @(New-Wl 'w' 'W' 'E:\__VIVE__\Documents\WeChat Files' 'data') -Volumes $script:Vols -KnownFolders $kf -SystemDrive 'C:'
        $adv[0].action | Should -Be 'keep'
        $adv[0].reason | Should -Match '已知文件夹'
    }
}

Describe '热数据判据' {
    It '热数据在 SSD/NVMe 上保持' {
        $adv = Get-RelocationAdvice -Workloads @(New-Wl 'w' 'PS' 'C:\Temp\scratch' 'cache' 'keep-fast') -Volumes $script:Vols -SystemDrive 'C:'
        $adv[0].action | Should -Be 'keep'
        $adv[0].reason | Should -Match '会自动清理'
    }
    It '热数据在机械盘上要搬回最快盘' {
        $adv = Get-RelocationAdvice -Workloads @(New-Wl 'w' 'PS' 'E:\scratch' 'cache' 'keep-fast') -Volumes $script:Vols -SystemDrive 'C:'
        $adv[0].action | Should -Be 'move'
        $adv[0].target | Should -Be 'C:'
    }
    It '冷数据在系统盘时搬到剩余空间最大的非系统盘' {
        $adv = Get-RelocationAdvice -Workloads @(New-Wl 'w' 'VM' 'C:\VMs' 'data') -Volumes $script:Vols -SystemDrive 'C:'
        $adv[0].action | Should -Be 'move'
        $adv[0].target | Should -Be 'E:'
    }
    It '配置类永不迁移' {
        $adv = Get-RelocationAdvice -Workloads @(New-Wl 'w' 'IDE' 'C:\cfg' 'config') -Volumes $script:Vols -SystemDrive 'C:'
        $adv[0].action | Should -Be 'skip'
    }
    It 'review 类要求人工确认' {
        $adv = Get-RelocationAdvice -Workloads @(New-Wl 'w' 'QQLive' 'C:\qqlive' 'review') -Volumes $script:Vols -SystemDrive 'C:'
        $adv[0].action | Should -Be 'ask'
    }
}