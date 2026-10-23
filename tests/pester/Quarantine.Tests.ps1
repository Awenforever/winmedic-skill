#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
    . (Join-Path $repo 'engine\lib\Journal.ps1')
    . (Join-Path $repo 'engine\lib\Action.ps1')
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
}
AfterAll {
    Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue
}

Describe '隔离区往返' {
    It '移动后能原样恢复' {
        $src = Join-Path $TestDrive 'roundtrip-data'
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'payload' -Encoding UTF8
        $item = [pscustomobject]@{ id = 'R1'; target = $src }
        $act = [pscustomobject]@{ kind = 'quarantine' }
        $r = Invoke-CdriveAction -Item $item -Action $act -RunId 'RUNRT'
        $r.ok | Should -BeTrue
        (Test-Path -LiteralPath $src) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $r.quarantinePath 'a.txt')) | Should -BeTrue

        $rec = [pscustomobject]@{ itemId = 'R1'; target = $src; quarantinePath = $r.quarantinePath; mode = 'quarantine' }
        $res = Restore-JournalQuarantine -Record $rec
        $res.ok | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $src 'a.txt')) | Should -BeTrue
    }
    It '原位置已存在时拒绝恢复' {
        $src = Join-Path $TestDrive 'conflict-data'
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'b.txt') -Value 'x' -Encoding UTF8
        $item = [pscustomobject]@{ id = 'R2'; target = $src }
        $act = [pscustomobject]@{ kind = 'quarantine' }
        $r = Invoke-CdriveAction -Item $item -Action $act -RunId 'RUNRT2'
        $r.ok | Should -BeTrue
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        $rec = [pscustomobject]@{ itemId = 'R2'; target = $src; quarantinePath = $r.quarantinePath; mode = 'quarantine' }
        $res = Restore-JournalQuarantine -Record $rec
        $res.ok | Should -BeFalse
        $res.detail | Should -Match '拒绝覆盖'
    }
    It '隔离区文件丢失时给出明确原因' {
        $rec = [pscustomobject]@{ itemId = 'R3'; target = (Join-Path $TestDrive 'whatever'); quarantinePath = (Join-Path $TestDrive 'no-such'); mode = 'quarantine' }
        $res = Restore-JournalQuarantine -Record $rec
        $res.ok | Should -BeFalse
        $res.detail | Should -Match '不存在'
    }
    It '同名冲突时隔离区自动加后缀不覆盖' {
        $src1 = Join-Path $TestDrive 'dup-src-1'
        $src2 = Join-Path $TestDrive 'dup-src-2'
        foreach ($s in @($src1, $src2)) { New-Item -ItemType Directory -Force -Path $s | Out-Null }
        Set-Content -LiteralPath (Join-Path $src1 'same.txt') -Value 'one' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $src2 'same.txt') -Value 'two' -Encoding UTF8
        $a1 = [pscustomobject]@{ kind = 'quarantine' }
        $r1 = Invoke-CdriveAction -Item ([pscustomobject]@{ id = 'R4'; target = (Join-Path $src1 'same.txt') }) -Action $a1 -RunId 'DUPRUN'
        $r2 = Invoke-CdriveAction -Item ([pscustomobject]@{ id = 'R4'; target = (Join-Path $src2 'same.txt') }) -Action $a1 -RunId 'DUPRUN'
        $r1.ok | Should -BeTrue
        $r2.ok | Should -BeTrue
        $r1.quarantinePath | Should -Not -Be $r2.quarantinePath
        (Test-Path -LiteralPath $r1.quarantinePath) | Should -BeTrue
        (Test-Path -LiteralPath $r2.quarantinePath) | Should -BeTrue
    }
}