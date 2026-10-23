#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Repo = $repo
    $script:IndexPath = Join-Path $repo 'playbook-index.md'
    $script:Index = if (Test-Path $script:IndexPath) { Get-Content -LiteralPath $script:IndexPath -Raw -Encoding UTF8 } else { '' }
}

Describe '路由表完整性' {
    It '索引文件存在且非空' {
        Test-Path $script:IndexPath | Should -BeTrue
        $script:Index.Length | Should -BeGreaterThan 200
    }
    It '索引中所有 playbook 链接都存在' {
        $ms = [regex]::Matches($script:Index, '\]\((playbooks/[^)]+\.md)\)')
        $ms.Count | Should -BeGreaterThan 3
        foreach ($m in $ms) {
            $rel = $m.Groups[1].Value.Replace('/', '\')
            $full = Join-Path $script:Repo $rel
            Test-Path -LiteralPath $full | Should -BeTrue
        }
    }
}

Describe '典型症状可路由' {
    It 'R1 C 盘爆满 指向 storage-disk-space-recovery' {
        $script:Index | Should -Match 'storage-disk-space-recovery'
        $script:Index | Should -Match 'C 盘红了'
    }
    It 'R2 开机慢 指向 boot-slow-boot-triage' {
        $script:Index | Should -Match 'boot-slow-boot-triage'
    }
    It 'R3 迁移不被当作清理' {
        $script:Index | Should -Match 'apps-migrate-to-another-drive'
        $script:Index | Should -Match '不得'
    }
    It 'R4 破坏性措辞先走 cleanup-protocol' {
        $script:Index | Should -Match 'cleanup-protocol'
        $script:Index | Should -Match '破坏性'
    }
}