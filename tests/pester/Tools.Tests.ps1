#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Tools.ps1')
    $script:WinMedicRoot = $repo
}

Describe '器械台' {
    It '目录可加载且字段齐全' {
        $all = @(Get-ToolCatalog)
        $all.Count | Should -BeGreaterThan 5
        foreach ($t in $all) {
            $t.id | Should -Not -BeNullOrEmpty
            $t.detect.type | Should -BeIn @('command', 'path', 'registry')
            ([int]$t.risk.tier -ge 1 -and [int]$t.risk.tier -le 4) | Should -BeTrue
        }
    }
    It '命令类器械能检测到' {
        $t = @(Get-ToolCatalog | Where-Object { $_.id -eq 'tool.netsh' })[0]
        (Test-ToolAvailable -Tool $t).available | Should -BeTrue
    }
    It '不存在的路径判定不可用' {
        $fake = [pscustomobject]@{ detect = [pscustomobject]@{ type = 'path'; value = 'C:\no\such\tool.exe' } }
        (Test-ToolAvailable -Tool $fake).available | Should -BeFalse
    }
    It '报告带 Tier 提示' {
        (Format-ToolsReport -Status @(Get-ToolsStatus)) | Should -Match 'Tier'
    }
}
