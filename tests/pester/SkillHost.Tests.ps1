#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:skillPath = Join-Path $repo 'SKILL.md'
    $script:front = @()
    $lines = Get-Content $script:skillPath -Encoding UTF8
    if ($lines[0].Trim() -ne '---') { throw 'SKILL.md 缺少 frontmatter' }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { break }
        $script:front += $lines[$i]
    }
}

Describe 'SKILL.md frontmatter（宿主解析契约）' {
    It 'name 与 description 存在' {
        @($script:front | Where-Object { $_ -match '^name:\s*\S' }).Count | Should -Be 1
        @($script:front | Where-Object { $_ -match '^description:\s*\S' }).Count | Should -Be 1
    }
    It '未加引号的值里不能再出现「冒号+空格」（会破坏 YAML）' {
        $bad = @()
        foreach ($line in $script:front) {
            if ($line -notmatch '^([A-Za-z_][\w-]*):\s*(.*)$') { continue }
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            if (-not $val) { continue }
            if ($val.StartsWith('"') -or $val.StartsWith("'")) { continue }
            if ($val.Contains(': ')) { $bad += ($key + ' => ' + $val.Substring(0, [Math]::Min(40, $val.Length))) }
        }
        $bad.Count | Should -Be 0 -Because ('未加引号且含冒号空格: ' + ($bad -join '; '))
    }
}

Describe 'MCP stdio 编码（客户端按 UTF-8 解码）' {
    It '工具输出是合法 UTF-8 且中文可读' {
        $mcp = Join-Path $repo 'engine\mcp\winmedic-mcp.ps1'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $mcp + '"'
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        # 严格 UTF-8：遇到非法字节直接抛错，避免「看起来能读但其实是乱码」
        $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false, $true)
        $p = [System.Diagnostics.Process]::Start($psi)
        try {
            Start-Sleep -Milliseconds 700
            $p.StandardInput.WriteLine('{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"winmedic_doctor","arguments":{}}}')
            $p.StandardInput.Flush()
            $line = $p.StandardOutput.ReadLine()
        } finally {
            try { $p.StandardInput.Close() } catch { }
            Start-Sleep -Milliseconds 200
            if (-not $p.HasExited) { $p.Kill() }
        }
        $line | Should -Match '环境自检'
        $line | Should -Not -Match '�'
    }
}