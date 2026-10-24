#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Recommendations.ps1')

    function New-Probe {
        param([string]$Id, $Data)
        [pscustomobject]@{ id = $Id; ok = $true; data = $Data }
    }
    function New-Findings {
        param([array]$Probes = @())
        [pscustomobject]@{ generatedAt = '2026-10-24T09:00:00+08:00'; probeSet = 'intake'; host = [pscustomobject]@{ computerName = 'T' }; probes = $Probes }
    }
}

Describe '建议生成' {
    It '空 findings 不产生建议' {
        @(Get-Recommendations -Findings (New-Findings)).Count | Should -Be 0
    }

    It '待重启产生 high 建议' {
        $f = New-Findings -Probes @((New-Probe 'probe.windows-update' ([pscustomobject]@{ pendingReboot = [pscustomobject]@{ pending = $true; reasons = @('CBS 待重启') } })))
        $r = Get-Recommendations -Findings $f
        @($r).Count | Should -Be 1
        @($r)[0].id | Should -Be 'rec.reboot-pending'
        @($r)[0].severity | Should -Be 'high'
    }

    It '恢复能力不足时建议建还原点并给出可执行动作' {
        $f = New-Findings -Probes @((New-Probe 'probe.recovery-readiness' ([pscustomobject]@{ level = 'poor'; risks = @('没有系统还原点') })))
        $r = Get-Recommendations -Findings $f
        @($r)[0].id | Should -Be 'rec.restore-point'
        @($r)[0].engineAction | Should -Be 'recovery.create-restore-point'
        @($r)[0].evidence | Should -Be 'ev.restore-point'
    }

    It '恢复能力 ready 时不产生该建议' {
        $f = New-Findings -Probes @((New-Probe 'probe.recovery-readiness' ([pscustomobject]@{ level = 'ready'; risks = @() })))
        @(Get-Recommendations -Findings $f).Count | Should -Be 0
    }

    It '备份 none 为 high，weak 为 medium' {
        $none = New-Findings -Probes @((New-Probe 'probe.backup-status' ([pscustomobject]@{ level = 'none'; note = '无备份' })))
        @(Get-Recommendations -Findings $none)[0].severity | Should -Be 'high'
        $weak = New-Findings -Probes @((New-Probe 'probe.backup-status' ([pscustomobject]@{ level = 'weak'; note = '只有还原点' })))
        @(Get-Recommendations -Findings $weak)[0].severity | Should -Be 'medium'
    }

    It '安全 risk 为 high，attention 为 medium' {
        $risk = New-Findings -Probes @((New-Probe 'probe.security-posture' ([pscustomobject]@{ verdict = 'risk'; issues = @('a', 'b') })))
        @(Get-Recommendations -Findings $risk)[0].severity | Should -Be 'high'
        $att = New-Findings -Probes @((New-Probe 'probe.security-posture' ([pscustomobject]@{ verdict = 'attention'; issues = @('a') })))
        @(Get-Recommendations -Findings $att)[0].severity | Should -Be 'medium'
    }

    It '问题设备与打印机异常各产生一条 medium' {
        $f = New-Findings -Probes @(
            (New-Probe 'probe.drivers' ([pscustomobject]@{ problemCount = 2; problemDevices = @([pscustomobject]@{ name = 'X'; meaning = '驱动未安装' }) })),
            (New-Probe 'probe.printers' ([pscustomobject]@{ problemCount = 1; problems = @([pscustomobject]@{ name = 'P1'; verdict = '脱机' }) }))
        )
        $r = Get-Recommendations -Findings $f
        @($r).Count | Should -Be 2
        ($r | Where-Object { $_.id -eq 'rec.device-problem' }).severity | Should -Be 'medium'
        ($r | Where-Object { $_.id -eq 'rec.printer-problem' }).severity | Should -Be 'medium'
    }

    It '代理不一致产生网络建议' {
        $f = New-Findings -Probes @((New-Probe 'probe.proxy-config' ([pscustomobject]@{ summary = [pscustomobject]@{ consistent = $false; note = '不一致' } })))
        @(Get-Recommendations -Findings $f)[0].id | Should -Be 'rec.proxy-mismatch'
    }

    It '启动项可禁用数量写进标题' {
        $items = @(1..3 | ForEach-Object { [pscustomobject]@{ name = ('svc' + $_); advice = 'optional-disable' } })
        $items += [pscustomobject]@{ name = 'keep'; advice = 'keep' }
        $f = New-Findings -Probes @((New-Probe 'probe.startup-items' ([pscustomobject]@{ count = 4; items = $items })))
        $r = Get-Recommendations -Findings $f
        @($r)[0].id | Should -Be 'rec.startup-bloat'
        @($r)[0].title | Should -Match '3'
        @($r)[0].severity | Should -Be 'low'
    }

    It '磁盘使用率 >= 90 才提示' {
        $high = New-Findings -Probes @((New-Probe 'probe.drive-space' ([pscustomobject]@{ usedPercent = 93; free = 5GB })))
        @(Get-Recommendations -Findings $high)[0].id | Should -Be 'rec.disk-pressure'
        $ok = New-Findings -Probes @((New-Probe 'probe.drive-space' ([pscustomobject]@{ usedPercent = 60; free = 100GB })))
        @(Get-Recommendations -Findings $ok).Count | Should -Be 0
    }

    It '软件缓存超 1 GB 产出 workload 建议（最多 3 条）' {
        $f = New-Findings -Probes @((New-Probe 'probe.workloads' ([pscustomobject]@{
            workloads = @(
                [pscustomobject]@{ id = 'workload.steam'; name = 'Steam'; installed = $true; cacheBytes = 3GB; dataBytes = 0; playbook = 'playbooks/apps-steam-triage.md' },
                [pscustomobject]@{ id = 'workload.latex'; name = 'TeX Live'; installed = $true; cacheBytes = 500MB; dataBytes = 0; playbook = 'playbooks/apps-latex-triage.md' }
            )
        })))
        $r = @(Get-Recommendations -Findings $f)
        @($r | Where-Object { $_.id -like 'rec.workload-cache:*' }).Count | Should -Be 1
        ($r | Where-Object { $_.id -eq 'rec.workload-cache:workload.steam' }).severity | Should -Be 'low'
    }
    It 'review 类超 1 GB 提示需人工确认' {
        $f = New-Findings -Probes @((New-Probe 'probe.workloads' ([pscustomobject]@{
            workloads = @([pscustomobject]@{ id = 'workload.tencent-video'; name = '腾讯视频'; installed = $true; cacheBytes = 0; dataBytes = 0; reviewBytes = 2GB; playbook = 'playbooks/apps-migrate-to-another-drive.md' })
        })))
        $r = @(@(Get-Recommendations -Findings $f) | Where-Object { $_.id -like 'rec.workload-review:*' })
        @($r).Count | Should -Be 1
        $r[0].title | Should -Match '需人工确认'
    }

    It 'Steam 游戏库超 100 GB 额外提示' {
        $f = New-Findings -Probes @((New-Probe 'probe.workloads' ([pscustomobject]@{
            workloads = @([pscustomobject]@{ id = 'workload.steam'; name = 'Steam'; installed = $true; cacheBytes = 0; dataBytes = 200GB; playbook = 'playbooks/apps-steam-triage.md' })
        })))
        @(@(Get-Recommendations -Findings $f) | Where-Object { $_.id -eq 'rec.steam-library' }).Count | Should -Be 1
    }
    It '代理链路不一致产出网络建议' {
        $f = New-Findings -Probes @((New-Probe 'probe.proxy-chain' ([pscustomobject]@{ consistent = $false; conflicts = @('system=8136', 'git=7890') })))
        $r = @(Get-Recommendations -Findings $f)[0]
        $r.id | Should -Be 'rec.proxy-chain'
        $r.detail | Should -Match '7890'
    }

    It 'Outlook 数据文件偏大或加载项异常时给出邮件建议' {
        $f = New-Findings -Probes @((New-Probe 'probe.mail-clients' ([pscustomobject]@{
            dataFiles = @([pscustomobject]@{ name = 'a.ost'; verdict = 'oversize' });
            problemAddinCount = 2
        })))
        $r = @(Get-Recommendations -Findings $f)[0]
        $r.id | Should -Be 'rec.mail-outlook'
        $r.severity | Should -Be 'medium'
        $r.detail | Should -Match '1 个数据文件偏大'
        $r.detail | Should -Match '2 个加载项'
    }
    It 'Outlook 正常时不产生建议' {
        $f = New-Findings -Probes @((New-Probe 'probe.mail-clients' ([pscustomobject]@{ dataFiles = @(); problemAddinCount = 0 })))
        @(Get-Recommendations -Findings $f).Count | Should -Be 0
    }

    It '疑似残留给出「引擎不自动删除」的说明' {
        $f = New-Findings -Probes @((New-Probe 'probe.app-residue' ([pscustomobject]@{ suspectCount = 2; suspectBytes = 1GB })))
        $r = Get-Recommendations -Findings $f
        @($r)[0].detail | Should -Match '不自动删除'
    }
}

Describe '建议渲染' {
    It '无建议时给出占位' {
        Format-RecommendationsMarkdown -Recommendations @() | Should -Match '无额外建议'
    }
    It 'high 排在 low 前面' {
        $recs = @(
            (New-Recommendation -Id 'r1' -Domain 'boot' -Severity 'low' -Title 'low-item'),
            (New-Recommendation -Id 'r2' -Domain 'updates' -Severity 'high' -Title 'high-item')
        )
        $md = Format-RecommendationsMarkdown -Recommendations $recs
        $md.IndexOf('high-item') | Should -BeLessThan $md.IndexOf('low-item')
    }
    It '可执行动作与人工 playbook 都会标注' {
        $r = @((New-Recommendation -Id 'r1' -Domain 'recovery' -Severity 'high' -Title 't' -EngineAction 'recovery.create-restore-point' -Playbook 'playbooks/setup-backup.md'))
        $md = Format-RecommendationsMarkdown -Recommendations $r
        $md | Should -Match '可执行'
        $md | Should -Match 'setup-backup'
    }
}