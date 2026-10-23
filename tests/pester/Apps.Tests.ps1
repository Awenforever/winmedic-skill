#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\probes\apps.ps1')
}

Describe '名称归一化' {
    It '去掉空格标点并小写' {
        ConvertTo-NormalizedName 'Adobe  CCXProcess!' | Should -Be 'adobeccxprocess'
    }
    It '保留中文' {
        ConvertTo-NormalizedName '网易云音乐' | Should -Be '网易云音乐'
    }
    It '空输入返回空串' {
        ConvertTo-NormalizedName '' | Should -Be ''
    }
}

Describe '名称相似判断' {
    It '互相包含视为相似' {
        Test-NameSimilar -DirName 'LogiOptionsPlus' -AppName 'Logitech Options+' | Should -BeTrue
    }
    It '共同前缀达到 5 字符视为相似' {
        Test-NameSimilar -DirName 'JetBrains.Rider' -AppName 'JetBrains Toolbox' | Should -BeTrue
    }
    It '无关名称不误判' {
        Test-NameSimilar -DirName 'SomeVendor' -AppName 'AnotherApp' | Should -BeFalse
    }
    It '过短名称不参与判断' {
        Test-NameSimilar -DirName 'ab' -AppName 'ab' | Should -BeFalse
    }
}

Describe '残留识别' {
    It '小目录不进入 suspects' {
        $dirs = @([pscustomobject]@{ name = 'TinyThing'; path = 'C:\x\TinyThing'; size = 10MB })
        $r = Get-ResidueSuspects -Dirs $dirs -Apps @('Whatever') -Exclude @()
        @($r).Count | Should -Be 0
    }
    It '白名单目录被排除' {
        $dirs = @([pscustomobject]@{ name = 'Package Cache'; path = 'C:\ProgramData\Package Cache'; size = 5GB })
        $r = Get-ResidueSuspects -Dirs $dirs -Apps @() -Exclude @('Package Cache')
        @($r).Count | Should -Be 0
    }
    It '无匹配程序的大目录进入 suspects' {
        $dirs = @([pscustomobject]@{ name = 'GhostApp2021'; path = 'C:\ProgramData\GhostApp2021'; size = 2GB })
        $r = Get-ResidueSuspects -Dirs $dirs -Apps @('Microsoft Office') -Exclude @()
        @($r).Count | Should -Be 1
        $r[0].verdict | Should -Be 'no-matching-app'
    }
    It '有匹配程序的大目录不算残留' {
        $dirs = @([pscustomobject]@{ name = 'Adobe'; path = 'C:\ProgramData\Adobe'; size = 3GB })
        $r = Get-ResidueSuspects -Dirs $dirs -Apps @('Adobe Acrobat Reader DC') -Exclude @()
        @($r).Count | Should -Be 0
    }
}

Describe '已安装程序探针' {
    It '返回结构化结果' {
        $r = Get-InstalledAppsProbe
        $r.id | Should -Be 'probe.installed-apps'
        $r.ok | Should -BeTrue
        $r.data.ContainsKey('apps') | Should -BeTrue
        @($r.data.apps).Count | Should -BeGreaterThan 0
    }
}