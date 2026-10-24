#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Remote.ps1')
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
}
AfterAll { Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue }

Describe 'target 解析' {
    It '别名形式' {
        $p = Get-RemoteTargetProfile -Target 'augenstern-adm'
        $p.valid | Should -BeTrue
        $p.host | Should -Be 'augenstern-adm'
        $p.user | Should -Be ''
    }
    It 'user@host 形式' {
        $p = Get-RemoteTargetProfile -Target 'lanagent@192.168.0.103'
        $p.user | Should -Be 'lanagent'
        $p.host | Should -Be '192.168.0.103'
    }
    It '空值与非法值被拒' {
        (Get-RemoteTargetProfile -Target '').valid | Should -BeFalse
        (Get-RemoteTargetProfile -Target 'a b@c').valid | Should -BeFalse
    }
    It '回环可识别' {
        (Get-RemoteTargetProfile -Target 'localhost').isLoopback | Should -BeTrue
        (Get-RemoteTargetProfile -Target '127.0.0.1').isLoopback | Should -BeTrue
        (Get-RemoteTargetProfile -Target 'example-host').isLoopback | Should -BeFalse
    }
}

Describe 'origin 标记' {
    It '给每个 probe 打标' {
        $f = [pscustomobject]@{ probes = @([pscustomobject]@{ id = 'p1' }, [pscustomobject]@{ id = 'p2' }) }
        $r = Set-FindingsOrigin -Findings $f -Origin 'remote:x'
        $r.probes[0].origin | Should -Be 'remote:x'
        $r.probes[1].origin | Should -Be 'remote:x'
    }
    It '已有 origin 不覆盖' {
        $f = [pscustomobject]@{ probes = @([pscustomobject]@{ id = 'p1'; origin = 'local' }) }
        (Set-FindingsOrigin -Findings $f -Origin 'remote:x').probes[0].origin | Should -Be 'local'
    }
}

Describe '落库命名与引导脚本' {
    It '文件名带上别名与探针集' {
        Get-RemoteFindingsName -Alias 'my-host' -Set 'intake' | Should -Be 'remote-my-host-intake-findings.json'
        Get-RemoteFindingsName -Alias 'a b/c' -Set 'storage' | Should -Be 'remote-a_b_c-storage-findings.json'
    }
    It '引导脚本含 Bypass/UTF8/CDRIVE_HOME/probe' {
        $s = New-RemoteStageScript -Root 'C:\t\wm' -RunId 'r1' -Set 'intake'
        $s | Should -Match 'Bypass'
        $s | Should -Match 'UTF8'
        $s | Should -Match 'CDRIVE_HOME'
        $s | Should -Match 'probe --set intake'
    }
}

Describe 'loopback 会话' {
    It '本机跑通并落库带 origin' {
        $repo2 = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $res = Invoke-RemoteSession -Target 'loopback-test' -Set 'storage' -Via 'local' -RepoRoot $repo2
        $res.ok | Should -BeTrue
        $res.exitCode | Should -Be 0
        Test-Path -LiteralPath $res.findingsPath | Should -BeTrue
        $f = Get-Content -LiteralPath $res.findingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $f.probes[0].origin | Should -Match 'remote:'
    }
}