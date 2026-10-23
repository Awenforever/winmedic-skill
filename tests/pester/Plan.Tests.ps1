#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
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

    It 'markdown 包含汇总、明细、证据三段' {
        $plan = New-CdrivePlan -Findings (New-TestFindings)
        $md = Format-PlanMarkdown -Plan $plan
        $md | Should -Match '## 汇总'
        $md | Should -Match '## 明细'
        $md | Should -Match '## 证据'
        $md | Should -Match 'sha256:'
    }
}