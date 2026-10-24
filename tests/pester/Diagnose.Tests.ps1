#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Trend.ps1')
    . (Join-Path $repo 'engine\lib\Diagnose.ps1')
    $script:WinMedicRoot = $repo
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
    function New-Fx {
        [pscustomobject]@{ probeSet = 'storage'; probes = @(
            [pscustomobject]@{ id = 'probe.host'; data = [pscustomobject]@{ computerName = 'H' } },
            [pscustomobject]@{ id = 'probe.drive-space'; data = [pscustomobject]@{ letter = 'C:'; total = 237GB; free = 40GB; usedPercent = 83 } },
            [pscustomobject]@{ id = 'probe.system-files'; data = [pscustomobject]@{ hiberfilSize = 8GB } },
            [pscustomobject]@{ id = 'probe.recycle-bin'; data = [pscustomobject]@{ total = 3GB } }
        ) }
    }
}
AfterAll { Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue }

Describe '诊断目录' {
    It '能按 id 取出并列出' {
        @(Get-DiagnosisCatalog).Count | Should -BeGreaterThan 1
        (Get-DiagnosisById -Id 'dx.cdisk-full').title | Should -Match 'C 盘'
        Get-DiagnosisById -Id 'nope' | Should -BeNullOrEmpty
    }
}

Describe '事实解析' {
    It '把指标解析成事实' {
        $d = Get-DiagnosisById -Id 'dx.cdisk-full'
        $r = Resolve-DiagnosisFacts -Diagnosis $d -Findings (New-Fx) -TrendRecords @()
        $r.case | Should -Be 'dx.cdisk-full'
        @($r.hypotheses).Count | Should -BeGreaterThan 3
        $h = @($r.hypotheses | Where-Object { $_.id -eq 'h.hiberfil' })[0]
        $h.checks[0].metric | Should -Be 'storage.hiberfilGB'
        $h.checks[0].currentValue | Should -Be 8
        $h.checks[0].available | Should -BeTrue
    }
    It '输出不含结论字段' {
        $d = Get-DiagnosisById -Id 'dx.cdisk-full'
        $r = Resolve-DiagnosisFacts -Diagnosis $d -Findings (New-Fx) -TrendRecords @()
        foreach ($h in @($r.hypotheses)) {
            $h.PSObject.Properties.Name -contains 'verdict' | Should -BeFalse
            $h.PSObject.Properties.Name -contains 'status' | Should -BeFalse
            foreach ($c in @($h.checks)) {
                $c.PSObject.Properties.Name -contains 'verdict' | Should -BeFalse
                $c.PSObject.Properties.Name -contains 'conclusion' | Should -BeFalse
            }
        }
    }
    It '缺失探针被列出' {
        $d = Get-DiagnosisById -Id 'dx.cdisk-full'
        $r = Resolve-DiagnosisFacts -Diagnosis $d -Findings (New-Fx) -TrendRecords @()
        @($r.missingProbes) | Should -Contain 'probe.workloads'
    }
    It '趋势样本不足时标 insufficient 且无值' {
        $d = Get-DiagnosisById -Id 'dx.cdisk-full'
        $r = Resolve-DiagnosisFacts -Diagnosis $d -Findings (New-Fx) -TrendRecords @()
        $g = @($r.hypotheses | Where-Object { $_.id -eq 'h.growth' })[0]
        $g.checks[0].available | Should -BeFalse
        $g.checks[0].source | Should -Match 'insufficient'
    }
    It '报告明确声明不给结论' {
        $d = Get-DiagnosisById -Id 'dx.cdisk-full'
        $r = Resolve-DiagnosisFacts -Diagnosis $d -Findings (New-Fx) -TrendRecords @()
        (Format-DiagnosisReport -Result $r) | Should -Match '不给结论'
    }
}
