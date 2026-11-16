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
    It '隐藏的联接（诱饵目录）不被误判' {
        $root = Join-Path $TestDrive 'usb-j'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $target = Join-Path $TestDrive 'bait-target'
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'x.dat') 'x'
        $link = Join-Path $root 'BAITLINK'
        New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
        [IO.File]::SetAttributes($link, [IO.FileAttributes]::Hidden)
        $d = Get-UsbDriveScan -Root $root
        @($d.hiddenDirs).Count | Should -Be 0
        $d.level | Should -Be 'clean'
    }
    It '同形字伪卷目录被判可疑' {
        $root = Join-Path $TestDrive 'usb-fv'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        # Usb Driv + 西里尔 е (U+0435)
        $fake = Join-Path $root ([string]([char]0x55) + [char]0x73 + [char]0x62 + ' ' + [char]0x44 + [char]0x72 + [char]0x69 + [char]0x76 + [char]0x435)
        [IO.Directory]::CreateDirectory($fake) | Out-Null
        Set-Content -LiteralPath (Join-Path $fake 'a.txt') 'x'
        Set-Content -LiteralPath (Join-Path $fake 'b.txt') 'x'
        Set-Content -LiteralPath (Join-Path $fake 'c.txt') 'x'
        $d = Get-UsbDriveScan -Root $root
        @($d.fakeVolumes).Count | Should -Be 1
        $d.fakeVolumes[0].signals | Should -Contain 'confusable-script'
        $d.fakeVolumes[0].suspicious | Should -BeTrue
        $d.level | Should -Be 'suspicious'
    }
    It '纯拉丁卷标名且含多项时判可疑' {
        $root = Join-Path $TestDrive 'usb-vl'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        $fake = Join-Path $root 'USB Drive'
        [IO.Directory]::CreateDirectory($fake) | Out-Null
        foreach ($n in @('a.txt','b.txt','c.txt')) { Set-Content -LiteralPath (Join-Path $fake $n) 'x' }
        $d = Get-UsbDriveScan -Root $root
        @($d.fakeVolumes).Count | Should -Be 1
        $d.fakeVolumes[0].signals | Should -Contain 'volume-label'
        $d.fakeVolumes[0].suspicious | Should -BeTrue
    }
    It '中文目录名不误判为伪卷' {
        $root = Join-Path $TestDrive 'usb-cjk'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        foreach ($n in @('测试图', '实验温度辐射数据', '旧电脑7018数据')) {
            $p = Join-Path $root $n
            [IO.Directory]::CreateDirectory($p) | Out-Null
            Set-Content -LiteralPath (Join-Path $p 'x.txt') 'x'
        }
        $d = Get-UsbDriveScan -Root $root
        @($d.fakeVolumes).Count | Should -Be 0
        $d.level | Should -Be 'clean'
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