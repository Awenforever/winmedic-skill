#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\lib\Repair.ps1')
    function New-RepairFixture {
        param([string]$Root, [string]$Source)
        New-Item -ItemType Directory -Force -Path (Join-Path $Root 'engine\lib') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $Source 'engine\lib') | Out-Null
        Set-Content -LiteralPath (Join-Path $Root 'engine\MANIFEST.txt') -Value 'lib/A.ps1' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $Source 'engine\MANIFEST.txt') -Value 'lib/A.ps1' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $Source 'engine\lib\A.ps1') -Value 'Write-Host A' -Encoding UTF8
    }
}

Describe 'repair 计划' {
    It '缺少文件识别为 missing' {
        $root = Join-Path $TestDrive 'r1'; $src = Join-Path $TestDrive 's1'
        New-RepairFixture -Root $root -Source $src
        $p = Get-RepairPlan -Root $root -SourcePath $src
        $p.available | Should -BeTrue
        ($p.todo | Where-Object { $_.rel -eq 'engine/lib/A.ps1' }).status | Should -Be 'missing'
    }
    It '内容不一致识别为 corrupt' {
        $root = Join-Path $TestDrive 'r2'; $src = Join-Path $TestDrive 's2'
        New-RepairFixture -Root $root -Source $src
        Set-Content -LiteralPath (Join-Path $root 'engine\lib\A.ps1') -Value 'Write-Host B' -Encoding UTF8
        $p = Get-RepairPlan -Root $root -SourcePath $src
        ($p.todo | Where-Object { $_.rel -eq 'engine/lib/A.ps1' }).status | Should -Be 'corrupt'
    }
    It '没有来源时 available=false' {
        $root = Join-Path $TestDrive 'r3'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'engine') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'engine\MANIFEST.txt') -Value 'lib/A.ps1' -Encoding UTF8
        $p = Get-RepairPlan -Root $root -SourcePath (Join-Path $TestDrive 'nope')
        $p.available | Should -BeFalse
    }
}

Describe 'repair 来源' {
    It 'zip 来源可展开并比对' {
        $root = Join-Path $TestDrive 'rz'; $src = Join-Path $TestDrive 'sz'
        New-RepairFixture -Root $root -Source $src
        $zip = Join-Path $TestDrive 'pkg.zip'
        Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip -Force
        $p = Get-RepairPlan -Root $root -SourcePath $zip
        $p.available | Should -BeTrue
        $p.source.kind | Should -Be 'zip'
        ($p.todo | Where-Object { $_.rel -eq 'engine/lib/A.ps1' }).status | Should -Be 'missing'
    }
}

Describe '引擎完整性' {
    It '缺文件时列出相对路径' {
        $root = Join-Path $TestDrive 'ri'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'engine\lib') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'engine\MANIFEST.txt') -Value @('lib/A.ps1','lib/B.ps1') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root 'engine\lib\A.ps1') -Value 'x' -Encoding UTF8
        $r = Get-EngineIntegrity -Root $root
        $r.ok | Should -BeFalse
        $r.checked | Should -Be 2
        $r.missing | Should -Contain 'engine/lib/B.ps1'
    }
}

Describe 'repair 执行' {
    It 'dry-run 不写文件' {
        $root = Join-Path $TestDrive 'r4'; $src = Join-Path $TestDrive 's4'
        New-RepairFixture -Root $root -Source $src
        $r = Invoke-Repair -Root $root -SourcePath $src
        $r.dryRun | Should -BeTrue
        Test-Path (Join-Path $root 'engine\lib\A.ps1') | Should -BeFalse
    }
    It '--yes 还原并备份' {
        $root = Join-Path $TestDrive 'r5'; $src = Join-Path $TestDrive 's5'
        New-RepairFixture -Root $root -Source $src
        $r = Invoke-Repair -Root $root -SourcePath $src -Yes
        $r.code | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $root 'engine\lib\A.ps1') -Raw).Trim() | Should -Be 'Write-Host A'
        Test-Path -LiteralPath $r.backupDir | Should -BeTrue
    }
}