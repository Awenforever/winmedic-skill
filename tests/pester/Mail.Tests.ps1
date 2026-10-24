#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\lib\Common.ps1')
    . (Join-Path $repo 'engine\probes\mail.ps1')
}

Describe '数据文件体积判定' {
    It '0 视为 empty' {
        Get-OstSizeVerdict -Bytes 0 | Should -Be 'empty'
    }
    It '分级正确' {
        Get-OstSizeVerdict -Bytes 1GB | Should -Be 'small'
        Get-OstSizeVerdict -Bytes 10GB | Should -Be 'normal'
        Get-OstSizeVerdict -Bytes 30GB | Should -Be 'large'
        Get-OstSizeVerdict -Bytes 60GB | Should -Be 'oversize'
    }
    It '边界值按包含处理' {
        Get-OstSizeVerdict -Bytes 25GB | Should -Be 'large'
        Get-OstSizeVerdict -Bytes 50GB | Should -Be 'oversize'
    }
}

Describe '加载项状态映射' {
    It '常见 LoadBehavior 语义' {
        Get-AddinLoadVerdict -LoadBehavior 3 | Should -Be 'loaded'
        Get-AddinLoadVerdict -LoadBehavior 2 | Should -Be 'not-loaded'
        Get-AddinLoadVerdict -LoadBehavior 0 | Should -Be 'disabled'
        Get-AddinLoadVerdict -LoadBehavior 8 | Should -Be 'loaded-on-demand'
    }
    It '未知值带原值返回' {
        Get-AddinLoadVerdict -LoadBehavior 99 | Should -Match 'unknown\(99\)'
    }
}

Describe '邮件客户端探针' {
    It '返回结构且字段齐全' {
        $r = Get-MailClientsProbe
        $r.id | Should -Be 'probe.mail-clients'
        $r.ok | Should -BeTrue
        foreach ($k in @('outlookInstalled', 'dataFiles', 'addinCount', 'problemAddinCount', 'dataTotalBytes')) {
            $r.data.ContainsKey($k) | Should -BeTrue
        }
    }
    It '问题加载项计数与列表一致' {
        $r = Get-MailClientsProbe
        $expect = @($r.data.addins | Where-Object { $_.state -in @('not-loaded', 'disabled') }).Count
        $r.data.problemAddinCount | Should -Be $expect
    }
}