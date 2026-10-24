#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Explain.ps1')
    $cat = Get-Content (Join-Path $repo 'catalog\actions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:Action = @($cat.actions | Where-Object { $_.id -eq 'storage.recycle-bin-empty' })[0]
    $script:Sheet = Format-PurgeConfirmation -Items @(
        [pscustomobject]@{ id = 'R1'; actionId = 'storage.recycle-bin-empty'; target = 'C:\$Recycle.Bin'; sizeBytes = 1073741824; action = $script:Action }
    ) -PlanHash 'abcdef1234567890' -Token 'DEADBEEF'
}

Describe '通俗说明' {
    It '每个动作都有 what/why/consequence' {
        $ex = Get-PlainExplanation -Action $script:Action -ActionId 'storage.recycle-bin-empty'
        $ex.what | Should -Not -BeNullOrEmpty
        $ex.why | Should -Not -BeNullOrEmpty
        $ex.consequence | Should -Not -BeNullOrEmpty
    }
    It '缺字段时诚实兜底，不编造' {
        $ex = Get-PlainExplanation -Action ([pscustomobject]@{ id = 'x' }) -ActionId 'x'
        $ex.why | Should -Match '未提供|不可逆'
    }
}

Describe '确认单内容' {
    It '六项说明齐全' {
        foreach ($k in @('这是什么', '在哪里', '有多大', '为什么可以删', '删了会怎样', '能不能撤回')) {
            $script:Sheet | Should -Match ([regex]::Escape($k))
        }
    }
    It '明确写出永久删除与不可恢复' {
        $script:Sheet | Should -Match '永久删除'
        $script:Sheet | Should -Match '不能'
    }
    It '给出回填令牌与退回方案' {
        $script:Sheet | Should -Match '--confirm-token DEADBEEF'
        $script:Sheet | Should -Match '隔离区'
    }
    It '包含每项的完整路径与体积' {
        $script:Sheet | Should -Match 'Recycle'
        $script:Sheet | Should -Match '1024'
    }
}

Describe '令牌绑定' {
    It '同输入同令牌' {
        $a = New-PurgeConfirmationToken -PlanHash 'h1' -Ids @('R1', 'R2')
        $b = New-PurgeConfirmationToken -PlanHash 'h1' -Ids @('R2', 'R1')
        $a | Should -Be $b
        $a.Length | Should -Be 8
    }
    It '换条目或换计划即失效' {
        $a = New-PurgeConfirmationToken -PlanHash 'h1' -Ids @('R1')
        $b = New-PurgeConfirmationToken -PlanHash 'h1' -Ids @('R1', 'R2')
        $c = New-PurgeConfirmationToken -PlanHash 'h2' -Ids @('R1')
        $a | Should -Not -Be $b
        $a | Should -Not -Be $c
    }
}