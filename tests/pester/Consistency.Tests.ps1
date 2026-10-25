#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:catalog = Join-Path $repo 'catalog'
    $script:read = { param($n) Get-Content (Join-Path $script:catalog $n) -Raw -Encoding UTF8 | ConvertFrom-Json }
}

Describe '症状触发的可达性' {
    It 'SKILL 里写着网络症状必须先跑 net-link' {
        $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $skill = Get-Content (Join-Path $repo 'SKILL.md') -Raw -Encoding UTF8
        $skill | Should -Match 'net-link'
        $skill | Should -Match 'Reconnecting|转圈'
    }
    It '存在 dx.link-flaky 且引用 net-link 指标' {
        $dx = & $script:read 'diagnoses.json'
        $d = @($dx.diagnoses | Where-Object { $_.id -eq 'dx.link-flaky' })
        $d.Count | Should -Be 1
        @($d[0].hypotheses | ForEach-Object { $_.checks } | ForEach-Object { $_.metric } | Where-Object { $_ -like 'network.*' }).Count | Should -BeGreaterThan 0
    }
}

Describe '诊断与指标的一致性' {
    It '每个诊断引用的指标都已注册' {
        $reg = & $script:read 'metrics.json'
        $names = @($reg.metrics | ForEach-Object { $_.name })
        $dx = & $script:read 'diagnoses.json'
        $bad = @()
        foreach ($d in @($dx.diagnoses)) {
            foreach ($h in @($d.hypotheses)) {
                foreach ($c in @($h.checks)) {
                    $mn = [string]$c.metric
                    if ($names -contains $mn) { continue }
                    $okDyn = $false
                    foreach ($ns in @($reg.dynamicNamespaces)) {
                        if (-not $ns) { continue }
                        $mt = [regex]::Match($mn, [string]$ns.pattern)
                        if (-not $mt.Success) { continue }
                        $tgPath = Join-Path $script:catalog ([string]$ns.definedIn -replace '.*/', '')
                        $tg = Get-Content $tgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $want = ([string]$ns.idTemplate).Replace('<id>', $mt.Groups['id'].Value)
                        if (@($tg.targets | ForEach-Object { $_.id }) -contains $want) { $okDyn = $true }
                        break
                    }
                    if (-not $okDyn) { $bad += ($d.id + ' -> ' + $mn) }
                }
            }
        }
        $bad.Count | Should -Be 0 -Because ('未注册指标: ' + ($bad -join '; '))
    }
    It '每个诊断依赖的探针都存在' {
        $probes = & $script:read 'probes.json'
        $ids = @($probes.probes | ForEach-Object { $_.id })
        $dx = & $script:read 'diagnoses.json'
        $bad = @()
        foreach ($d in @($dx.diagnoses)) {
            foreach ($rp in @($d.requiredProbes)) { if ($ids -notcontains [string]$rp) { $bad += ($d.id + ' -> ' + $rp) } }
        }
        $bad.Count | Should -Be 0 -Because ('缺失探针: ' + ($bad -join '; '))
    }
    It '注册表里的指标名唯一' {
        $reg = & $script:read 'metrics.json'
        $names = @($reg.metrics | ForEach-Object { $_.name })
        @($names | Select-Object -Unique).Count | Should -Be $names.Count
    }
}