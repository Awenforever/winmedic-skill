#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Relocation.ps1')
    $script:Vols = @{ 'C:' = @{ media = 'NVMe'; rank = 4; totalGB = 240; freeGB = 40 }; 'E:' = @{ media = 'HDD'; rank = 1; totalGB = 1800; freeGB = 800 } }
}

Describe '决策清单' {
    It '固定三条且覆盖三个误判点' {
        $c = Get-RelocationChecklist
        @($c).Count | Should -Be 3
        ($c -join ' ') | Should -Match '已知文件夹'
        ($c -join ' ') | Should -Match '热数据'
        ($c -join ' ') | Should -Match '绝对路径'
    }
}

Describe '事实层不含判断' {
    It '事实字段齐全且不含 action/target 这类结论字段' {
        $tmp = Join-Path $env:TEMP ('facts-' + [guid]::NewGuid().ToString('N').Substring(0,6))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $wl = [pscustomobject]@{ id = 'w'; name = 'W'; installed = $true; items = @([pscustomobject]@{ label = 'L'; kind = 'cache'; path = $tmp; size = 1GB }) }
        $facts = Get-RelocationFacts -Workloads @($wl) -Volumes $script:Vols -KnownFolders ([ordered]@{}) -DeclaredPaths @{}
        @($facts).Count | Should -Be 1
        $f = $facts[0]
        foreach ($k in @('path', 'drive', 'media', 'exists', 'knownFolder', 'declaredPath', 'kind', 'size')) {
            $f.PSObject.Properties.Name -contains $k | Should -BeTrue
        }
        $f.PSObject.Properties.Name -contains 'action' | Should -BeFalse
        $f.exists | Should -BeTrue
        $f.knownFolder | Should -Be ''
        Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
    }
    It '能识别已知文件夹归属' {
        $tmp = Join-Path $env:TEMP ('kfx-' + [guid]::NewGuid().ToString('N').Substring(0,6))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $wl = [pscustomobject]@{ id = 'w'; name = 'W'; installed = $true; items = @([pscustomobject]@{ label = 'L'; kind = 'data'; path = (Join-Path $tmp 'sub'); size = 1GB }) }
        $facts = Get-RelocationFacts -Workloads @($wl) -Volumes $script:Vols -KnownFolders ([ordered]@{ Documents = $tmp }) -DeclaredPaths @{}
        $facts[0].knownFolder | Should -Be 'Documents'
        Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
    }
}

Describe '默认建议被明确标注' {
    It '建议带 policySource=default-hint' {
        $wl = [pscustomobject]@{ id = 'w'; name = 'W'; installed = $true; items = @([pscustomobject]@{ label = 'L'; kind = 'data'; path = 'C:\x'; size = 1GB }) }
        $adv = Get-RelocationAdvice -Workloads @($wl) -Volumes $script:Vols -KnownFolders ([ordered]@{}) -SystemDrive 'C:'
        $adv[0].policySource | Should -Be 'default-hint'
    }
}