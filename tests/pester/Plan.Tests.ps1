#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
    . (Join-Path $repo 'engine\lib\Profile.ps1')
    . (Join-Path $repo 'engine\lib\Recommendations.ps1')
    . (Join-Path $repo 'engine\lib\Plan.ps1')
    $script:WinMedicRoot = $repo

    function New-TestFindings {
        [pscustomobject]@{
            schemaVersion = 1
            host = [pscustomobject]@{ computerName = 'TEST'; osCaption = 'Windows'; osBuild = '26100'; isAdmin = $false; psVersion = '5.1' }
            candidates = @(
                [pscustomobject]@{ actionId = 'storage.hiberfil-off'; target = 'C:\hiberfil.sys'; kind = 'command'; size = 6GB; count = 1; notes = '' }
                [pscustomobject]@{ actionId = 'storage.panther-remove'; target = 'C:\Windows\Panther'; kind = 'dir'; size = 1GB; count = 10; notes = '' }
                [pscustomobject]@{ actionId = 'storage.recycle-bin-empty'; target = 'C:\RecycleBinProbe'; kind = 'dir'; size = 3MB; count = 2; notes = '' }
                [pscustomobject]@{ actionId = 'storage.edge-cache'; target = 'C:\Windows\System32\EdgeCache'; kind = 'dir'; size = 2GB; count = 5; notes = '' }
            )
        }
    }
}

Describe '计划哈希稳定性' {
    It 'JSON 往返后哈希不变（真实缺陷回归）' {
        $items = @(
            [pscustomobject]@{ id = 'R1'; actionId = 'storage.software-distribution-download'; target = 'C:\Windows\SoftwareDistribution\Download'; size = [int64]97891982; tier = [int32]2 },
            [pscustomobject]@{ id = 'R2'; actionId = 'storage.edge-cache'; target = 'C:\Users\k\AppData\Local\Microsoft\Edge\User Data\Default\Cache'; size = [int64]125829120; tier = [int32]2 }
        )
        $h1 = Get-PlanHash -Items $items
        $back = (($items) | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
        $h2 = Get-PlanHash -Items $back
        $h1 | Should -Be $h2
    }
    It '顺序不同但内容相同 -> 哈希一致' {
        $a = @([pscustomobject]@{ id='R1'; actionId='x'; target='C:\a'; size=[int64]1; tier=2 }, [pscustomobject]@{ id='R2'; actionId='y'; target='C:\b'; size=[int64]2; tier=2 })
        $b = @([pscustomobject]@{ id='R2'; actionId='y'; target='C:\b'; size=[int64]2; tier=2 }, [pscustomobject]@{ id='R1'; actionId='x'; target='C:\a'; size=[int64]1; tier=2 })
        (Get-PlanHash -Items $a) | Should -Be (Get-PlanHash -Items $b)
    }
    It '内容变化 -> 哈希变化' {
        $a = @([pscustomobject]@{ id='R1'; actionId='x'; target='C:\a'; size=[int64]1; tier=2 })
        $b = @([pscustomobject]@{ id='R1'; actionId='x'; target='C:\a'; size=[int64]1; tier=3 })
        (Get-PlanHash -Items $a) | Should -Not -Be (Get-PlanHash -Items $b)
    }
}

Describe '方案生成' {
    It '只保留足够大的项，过小项被排除' {
        $plan = New-CdrivePlan -Findings (New-TestFindings)
        $itemTargets = @($plan.items | ForEach-Object { $_['target'] })
        $itemTargets.Count | Should -Be 2
        ($itemTargets -join '|') | Should -Not -Match 'RecycleBinProbe'
        $exReasons = @($plan.excluded | ForEach-Object { $_['reason'] })
        ($exReasons -join '|') | Should -Match '体积过小'
    }

    It '红线路径进入 excluded 且不进入 items' {
        $plan = New-CdrivePlan -Findings (New-TestFindings)
        $itemTargets = @($plan.items | ForEach-Object { $_['target'] })
        $excTargets = @($plan.excluded | ForEach-Object { $_['target'] })
        ($itemTargets -join '|') | Should -Not -Match 'System32'
        ($excTargets -join '|') | Should -Match 'System32'
        $exReasons = @($plan.excluded | ForEach-Object { $_['reason'] })
        ($exReasons -join '|') | Should -Match '红线'
    }

    It '同一输入生成稳定哈希且可被校验' {
        $p1 = New-CdrivePlan -Findings (New-TestFindings)
        $p2 = New-CdrivePlan -Findings (New-TestFindings)
        $p1.planHash | Should -Be $p2.planHash
        (Test-PlanIntegrity -Plan $p1).Ok | Should -BeTrue
    }

    It '篡改条目后校验失败' {
        $plan = New-CdrivePlan -Findings (New-TestFindings)
        $plan.items[0]['size'] = 999GB
        (Test-PlanIntegrity -Plan $plan).Ok | Should -BeFalse
    }

    It '方案对象带 recommendations 字段' {
        $plan = New-CdrivePlan -Findings (New-TestFindings)
        $plan.Keys -contains 'recommendations' | Should -BeTrue
        @($plan.recommendations).Count | Should -Be 0
    }

    It 'markdown 含建议段' {
        $plan = New-CdrivePlan -Findings (New-TestFindings)
        (Format-PlanMarkdown -Plan $plan) | Should -Match '建议（按优先级）'
    }

    It 'markdown 包含汇总、明细、证据三段' {
        $plan = New-CdrivePlan -Findings (New-TestFindings)
        $md = Format-PlanMarkdown -Plan $plan
        $md | Should -Match '## 汇总'
        $md | Should -Match '## 明细'
        $md | Should -Match '## 证据'
        $md | Should -Match 'sha256:'
    }
}