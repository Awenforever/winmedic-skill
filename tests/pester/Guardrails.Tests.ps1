#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Safety.ps1')
    . (Join-Path $repo 'engine\lib\Journal.ps1')
    $env:CDRIVE_HOME = Join-Path $TestDrive 'cdrive'
    New-Item -ItemType Directory -Force -Path $env:CDRIVE_HOME | Out-Null
}
AfterAll { Remove-Item Env:\CDRIVE_HOME -ErrorAction SilentlyContinue }

Describe '不可逆操作双闸' {
    It '非 purge 放行' {
        (Test-PurgeAllowed).allow | Should -BeTrue
    }
    It 'purge 但未显式接受 -> 拒绝' {
        $r = Test-PurgeAllowed -Purge
        $r.allow | Should -BeFalse
        $r.reason | Should -Match 'accept-irreversible'
    }
    It 'purge + 显式接受 -> 放行' {
        (Test-PurgeAllowed -Purge -AcceptIrreversible).allow | Should -BeTrue
    }
}

Describe '引擎自身目录红线' {
    It '状态目录及其子路径拒绝' {
        Test-StateDirPath -Path $env:CDRIVE_HOME | Should -BeTrue
        Test-StateDirPath -Path (Join-Path $env:CDRIVE_HOME 'quarantine') | Should -BeTrue
    }
    It '普通路径不受影响' {
        Test-StateDirPath -Path 'C:\Windows\Panther' | Should -BeFalse
    }
}

Describe '预写日志与中断恢复' {
    It 'begin+done 成对时不算孤儿' {
        $rid = 'RUNPAIR'
        Write-JournalRecord -RunId $rid -Record @{ itemId = 'R1'; actionId = 'a'; target = 'C:\x'; phase = 'begin' }
        Write-JournalRecord -RunId $rid -Record @{ itemId = 'R1'; actionId = 'a'; target = 'C:\x'; phase = 'done'; ok = $true }
        @(Get-JournalOrphans -RunId $rid).Count | Should -Be 0
    }
    It '只有 begin 且隔离区有内容 -> 识别为可救回的中断项' {
        $rid = 'RUNORPH'
        $target = Join-Path $TestDrive 'orphan-target'
        Write-JournalRecord -RunId $rid -Record @{ itemId = 'R9'; actionId = 'storage.panther-remove'; target = $target; phase = 'begin' }
        $qdir = Get-QuarantineDirFor -RunId $rid -ItemId 'R9'
        New-Item -ItemType Directory -Force -Path $qdir | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $qdir 'payload') | Out-Null
        $o = @(Get-JournalOrphans -RunId $rid)
        $o.Count | Should -Be 1
        $o[0].itemId | Should -Be 'R9'
        $o[0].hasQuarantine | Should -BeTrue
    }
    It '只有 begin 且隔离区为空 -> 标记未实际移动' {
        $rid = 'RUNEMPTY'
        Write-JournalRecord -RunId $rid -Record @{ itemId = 'R8'; actionId = 'a'; target = (Join-Path $TestDrive 'never') ; phase = 'begin' }
        $o = @(Get-JournalOrphans -RunId $rid)
        $o.Count | Should -Be 1
        $o[0].hasQuarantine | Should -BeFalse
    }
}