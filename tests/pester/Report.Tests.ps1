#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Report.ps1')
    function New-TestFindings {
        [pscustomobject]@{
            generatedAt = '2026-10-24T00:00:00+08:00'
            probeSet = 'storage'
            host = [pscustomobject]@{ computerName = 'TESTPC'; osCaption = 'Windows 11 Pro'; osBuild = '26200' }
            probes = @(
                [pscustomobject]@{ id = 'probe.drive-space'; ok = $true; data = [pscustomobject]@{ total = 250GB; free = 50GB; used = 200GB; usedPercent = 80 } },
                [pscustomobject]@{ id = 'probe.winsxs'; ok = $false; data = [pscustomobject]@{} }
            )
        }
    }
    function New-TestPlan {
        [pscustomobject]@{
            items = @(
                [ordered]@{ id = 'R1'; actionId = 'storage.panther-remove'; target = 'C:\Windows\Panther'; size = 2GB; tier = 1 },
                [ordered]@{ id = 'R2'; actionId = 'storage.edge-cache'; target = 'C:\Edge\Cache'; size = 1GB; tier = 2 }
            )
            excluded = @([pscustomobject]@{ target = 'C:\Windows\System32\x'; reason = '命中红线模式: \windows\system32' })
        }
    }
}

Describe '报告生成' {
    It '包含五个固定段落' {
        $md = Format-WinMedicReport -Findings (New-TestFindings) -Plan (New-TestPlan)
        foreach ($s in @('## 1. 现状', '## 2. 找到什么', '## 3. 做了什么', '## 4. 验证结果', '## 5. 没做什么')) {
            $md | Should -Match ([regex]::Escape($s))
        }
    }
    It '现状段带主机与容量' {
        $md = Format-WinMedicReport -Findings (New-TestFindings) -Plan (New-TestPlan)
        $md | Should -Match 'TESTPC'
        $md | Should -Match '80%'
    }
    It '未取证的探针被列出' {
        $md = Format-WinMedicReport -Findings (New-TestFindings) -Plan (New-TestPlan)
        $md | Should -Match 'probe.winsxs'
    }
    It '只读体检明确写未执行写操作' {
        $md = Format-WinMedicReport -Findings (New-TestFindings) -Plan (New-TestPlan)
        $md | Should -Match '只读体检'
    }
    It '有 journal 时列出动作与空间变化' {
        $rec = [pscustomobject]@{ itemId = 'R1'; actionId = 'storage.panther-remove'; ok = $true; result = 'ok'; freeBefore = 50GB; freeAfter = 52GB; pendingReboot = $false; verify = @([pscustomobject]@{ rule = 'path_absent'; ok = $true; detail = '已删除' }) }
        $md = Format-WinMedicReport -Findings (New-TestFindings) -Plan (New-TestPlan) -JournalRecords @($rec) -RunId 'RUN1'
        $md | Should -Match 'RUN1'
        $md | Should -Match 'storage.panther-remove'
        $md | Should -Match '2 GB'
        $md | Should -Match 'path_absent'
    }
    It '排除项出现在第 5 段' {
        $md = Format-WinMedicReport -Findings (New-TestFindings) -Plan (New-TestPlan)
        $md | Should -Match '命中红线模式'
    }
}