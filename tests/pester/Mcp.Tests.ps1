#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Server = Join-Path $repo 'engine\mcp\winmedic-mcp.ps1'
    $script:InFile = Join-Path $TestDrive 'mcp-in.jsonl'
    $script:OutFile = Join-Path $TestDrive 'mcp-out.jsonl'
    $script:ErrFile = Join-Path $TestDrive 'mcp-err.log'

    function Invoke-Mcp {
        param([string[]]$Lines2, [string[]]$ServerArgs = @())
        [IO.File]::WriteAllLines($script:InFile, $Lines2, (New-Object Text.UTF8Encoding($false)))
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Server) + $ServerArgs
        $p = Start-Process -FilePath 'powershell' -ArgumentList $argList -RedirectStandardInput $script:InFile -RedirectStandardOutput $script:OutFile -RedirectStandardError $script:ErrFile -NoNewWindow -PassThru
        [void]$p.WaitForExit(120000)
        $out = @(Get-Content -LiteralPath $script:OutFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
        return $out
    }
}

Describe 'MCP 协议' {
    It 'initialize 返回协议版本与服务器信息' {
        $out = Invoke-Mcp -Lines2 @('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
        @($out).Count | Should -Be 1
        $out[0].result.protocolVersion | Should -Be '2024-11-05'
        $out[0].result.serverInfo.name | Should -Be 'winmedic'
        ($out[0].result.capabilities.PSObject.Properties.Name -contains 'tools') | Should -BeTrue
    }

    It 'tools/list 返回 10 个工具且都带 schema' {
        $out = Invoke-Mcp -Lines2 @('{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
        $tools = @($out[0].result.tools)
        $tools.Count | Should -Be 10
        foreach ($t in $tools) {
            $t.name | Should -Not -BeNullOrEmpty
            $t.description | Should -Not -BeNullOrEmpty
            $t.inputSchema.type | Should -Be 'object'
        }
    }

    It '未知方法返回 -32601，未知工具返回 -32602' {
        $out = Invoke-Mcp -Lines2 @(
            '{"jsonrpc":"2.0","id":1,"method":"nope"}',
            '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nope","arguments":{}}}'
        )
        $out[0].error.code | Should -Be -32601
        $out[1].error.code | Should -Be -32602
    }

    It '通知不产生响应' {
        $out = Invoke-Mcp -Lines2 @('{"jsonrpc":"2.0","method":"notifications/initialized"}')
        @($out).Count | Should -Be 0
    }
}

Describe 'MCP 安全边界' {
    It 'apply 缺 yes 时拒绝执行' {
        $out = Invoke-Mcp -Lines2 @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"winmedic_apply","arguments":{"ids":["R1"]}}}')
        $out[0].result.isError | Should -BeTrue
        $out[0].result.content[0].text | Should -Match 'yes=true'
    }

    It 'apply 缺 ids 与 action 时拒绝' {
        $out = Invoke-Mcp -Lines2 @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"winmedic_apply","arguments":{"yes":true}}}')
        $out[0].result.isError | Should -BeTrue
        $out[0].result.content[0].text | Should -Match 'ids'
    }

    It '只读模式禁用 apply' {
        $out = Invoke-Mcp -ServerArgs @('-ReadOnly') -Lines2 @('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"winmedic_apply","arguments":{"ids":["R1"],"yes":true}}}')
        $out[0].result.isError | Should -BeTrue
        $out[0].result.content[0].text | Should -Match 'ReadOnly'
    }
}