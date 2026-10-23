#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
    . (Join-Path $repo 'engine\lib\Profile.ps1')
    . (Join-Path $repo 'engine\lib\Plan.ps1')
    $script:WinMedicRoot = $repo
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
}
AfterAll {
    Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue
}

Describe '保留项匹配' {
    It '空模式不排除任何东西' {
        Test-ExcludedPath -Target 'C:\Temp\x' -Patterns @() | Should -BeFalse
    }
    It '精确路径命中' {
        Test-ExcludedPath -Target 'C:\Users\a\WeChat Files' -Patterns @('C:\Users\a\WeChat Files') | Should -BeTrue
    }
    It '子路径也算命中' {
        Test-ExcludedPath -Target 'C:\Users\a\WeChat Files\msg' -Patterns @('C:\Users\a\WeChat Files') | Should -BeTrue
    }
    It '通配符命中' {
        Test-ExcludedPath -Target 'D:\Games\Steam\steamapps' -Patterns @('D:\*') | Should -BeTrue
    }
    It '大小写不敏感' {
        Test-ExcludedPath -Target 'c:\users\A\WeChat Files' -Patterns @('C:\Users\a\WeChat Files') | Should -BeTrue
    }
    It '不相关路径不命中' {
        Test-ExcludedPath -Target 'C:\Windows\Panther' -Patterns @('C:\Users\a\WeChat Files') | Should -BeFalse
    }
    It '给出命中原因' {
        Get-ExclusionReason -Target 'D:\Games\x' -Patterns @('D:\*') | Should -Match '用户保留项'
    }
}

Describe '保留项持久化' {
    It '新增后能读回' {
        Add-CdriveExclusion -Pattern 'C:\KeepMe\' | Out-Null
        $p = Get-CdriveProfile
        @($p.exclude) | Should -Contain 'C:\KeepMe'
    }
    It '重复新增不产生重复项' {
        Add-CdriveExclusion -Pattern 'C:\KeepMe' | Out-Null
        $p = Get-CdriveProfile
        @($p.exclude | Where-Object { $_ -eq 'C:\KeepMe' }).Count | Should -Be 1
    }
    It '可以移除' {
        Remove-CdriveExclusion -Pattern 'C:\KeepMe' | Out-Null
        @((Get-CdriveProfile).exclude) | Should -Not -Contain 'C:\KeepMe'
    }
}

Describe '方案阶段的保留项拦截' {
    It '命中保留项的候选项进入 excluded 且不进 items' {
        Add-CdriveExclusion -Pattern 'C:\Windows\Panther' | Out-Null
        $findings = [pscustomobject]@{
            schemaVersion = 1
            host = [pscustomobject]@{ computerName = 'T'; osCaption = 'W'; osBuild = '1'; isAdmin = $false; psVersion = '5.1' }
            candidates = @(
                [pscustomobject]@{ actionId = 'storage.panther-remove'; target = 'C:\Windows\Panther'; kind = 'dir'; size = 2GB; count = 1; notes = '' },
                [pscustomobject]@{ actionId = 'storage.hiberfil-off'; target = 'C:\hiberfil.sys'; kind = 'command'; size = 6GB; count = 1; notes = '' }
            )
        }
        $plan = New-CdrivePlan -Findings $findings
        $itemTargets = @($plan.items | ForEach-Object { $_['target'] })
        ($itemTargets -join '|') | Should -Not -Match 'Panther'
        $excReasons = @($plan.excluded | ForEach-Object { $_['reason'] })
        ($excReasons -join '|') | Should -Match '用户保留项'
        Remove-CdriveExclusion -Pattern 'C:\Windows\Panther' | Out-Null
    }
}