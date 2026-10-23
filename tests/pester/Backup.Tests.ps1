#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\probes\backup.ps1')
}

Describe '备份裁决' {
    It '什么都没有时判 none' {
        $r = Get-BackupVerdict
        $r.level | Should -Be 'none'
        $r.note | Should -Match '没有任何备份'
    }
    It '只有还原点/卷影副本时判 weak' {
        $r = Get-BackupVerdict -RestorePoints 3 -ShadowCopies 2
        $r.level | Should -Be 'weak'
        $r.note | Should -Match '不能替代'
    }
    It '有用户数据级备份时判 ok' {
        $r = Get-BackupVerdict -FileHistory $true
        $r.level | Should -Be 'ok'
    }
    It 'OneDrive 文件夹备份也算 ok' {
        (Get-BackupVerdict -OneDriveKfm $true).level | Should -Be 'ok'
    }
    It '来源列表反映实际命中项' {
        $r = Get-BackupVerdict -FileHistory $true -RestorePoints 2
        ($r.sources -join '|') | Should -Match '文件历史'
        ($r.sources -join '|') | Should -Match '还原点'
    }
}

Describe '备份探针' {
    It '返回等级与各来源状态' {
        $r = Get-BackupStatusProbe
        $r.id | Should -Be 'probe.backup-status'
        $r.ok | Should -BeTrue
        $r.data.level | Should -BeIn @('none', 'weak', 'ok')
        $r.data.ContainsKey('fileHistory') | Should -BeTrue
        $r.data.ContainsKey('oneDrive') | Should -BeTrue
        $r.data.ContainsKey('systemImage') | Should -BeTrue
    }
}