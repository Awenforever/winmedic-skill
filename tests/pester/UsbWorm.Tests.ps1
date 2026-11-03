#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\probes\usb.ps1')
}

Describe '快捷方式特征' {
    It 'cmd.exe + DrvSvc 参数判可疑' {
        $r = @(Test-UsbShortcutPattern -Target 'C:\Windows\System32\cmd.exe' -Args '/c start ￿ & start ￿\DrvSvcsrMgrsvr.exe')
        $r.Count | Should -BeGreaterThan 0
    }
    It '普通程序不判可疑' {
        @(Test-UsbShortcutPattern -Target 'C:\Program Files\App\app.exe' -Args '--normal').Count | Should -Be 0
    }
}

Describe 'U 盘扫描' {
    It '隐藏目录 + 载荷 + autorun 判感染' {
        $root = Join-Path $TestDrive 'usb1'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $hid = Join-Path $root 'x'
        [IO.Directory]::CreateDirectory($hid) | Out-Null
        Set-Content -LiteralPath (Join-Path $hid 'data.txt') 'x'
        [IO.File]::SetAttributes($hid, [IO.FileAttributes]::Hidden)
        Set-Content -LiteralPath (Join-Path $root 'DrvSvc_sample.dat') 'x'
        Set-Content -LiteralPath (Join-Path $root 'autorun.inf') '[autorun]'
        $d = Get-UsbDriveScan -Root $root
        $d.level | Should -Be 'infected'
        @($d.hiddenDirs).Count | Should -BeGreaterThan 0
        $d.autorun | Should -BeTrue
        @($d.payloads).Count | Should -BeGreaterThan 0
    }
    It '干净目录判 clean' {
        $root = Join-Path $TestDrive 'usb2'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'note.txt') 'hello'
        (Get-UsbDriveScan -Root $root).level | Should -Be 'clean'
    }
    It '探针返回汇总计数' {
        $root = Join-Path $TestDrive 'usb3'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $p = Get-UsbWormProbe -Roots @($root)
        $p.id | Should -Be 'probe.usb-worm'
        $p.data.counts.drives | Should -Be 1
    }
}