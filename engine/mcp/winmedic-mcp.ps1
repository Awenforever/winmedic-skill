#Requires -Version 5.1
<#
.SYNOPSIS
  WinMedic MCP 服务器（stdio / JSON-RPC 2.0）。
.DESCRIPTION
  让不支持直接跑脚本的宿主（Claude Desktop、各类 MCP 客户端）也能用 WinMedic。
  设计约束：
    - 只通过引擎执行，不自己拼命令；
    - 默认只读工具全开，写工具（apply/restore）必须显式 yes=true；
    - -ReadOnly 参数可整体禁用写工具；
    - 所有日志走 stderr，stdout 只允许 JSON-RPC。
.EXAMPLE
  .\winmedic-mcp.ps1            # 全功能
.EXAMPLE
  .\winmedic-mcp.ps1 -ReadOnly  # 只读审查模式
#>
[CmdletBinding()]
param(
    [switch]$ReadOnly,
    [string]$EnginePath
)

$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $script:Root) { $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$script:Engine = if ($EnginePath) { $EnginePath } else { Join-Path $script:Root 'engine\winmedic.ps1' }
$script:Version = ((Get-Content -LiteralPath (Join-Path $script:Root 'VERSION') -Raw -ErrorAction SilentlyContinue) -as [string])
if (-not $script:Version) { $script:Version = '0.0.0' }
$script:Version = $script:Version.Trim()

function Write-Log2 { param([string]$Message) [Console]::Error.WriteLine('[winmedic-mcp] ' + $Message) }

function Send-Raw {
    param([Parameter(Mandatory)]$Object)
    [Console]::Out.WriteLine(($Object | ConvertTo-Json -Depth 20 -Compress))
    [Console]::Out.Flush()
}

function Send-Result {
    param($Id, $Result)
    Send-Raw ([ordered]@{ jsonrpc = '2.0'; id = $Id; result = $Result })
}

function Send-Error {
    param($Id, [int]$Code, [string]$Message)
    Send-Raw ([ordered]@{ jsonrpc = '2.0'; id = $Id; error = [ordered]@{ code = $Code; message = $Message } })
}

function Invoke-Engine {
    param([string[]]$EngineArgs)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:Engine @EngineArgs 2>&1 | Out-String
    return @{ code = $LASTEXITCODE; text = $out }
}

function New-ToolResult {
    param([bool]$IsError, [string]$Text)
    return [ordered]@{ content = @([ordered]@{ type = 'text'; text = $Text }); isError = $IsError }
}

# ---------------- 工具定义 ----------------
$script:Tools = @(
    [ordered]@{
        name = 'winmedic_doctor'
        description = '环境自检：系统版本、PowerShell、是否管理员、WizTree 可用性、磁盘概况。只读。'
        inputSchema = [ordered]@{ type = 'object'; properties = [ordered]@{}; additionalProperties = $false }
    },
    [ordered]@{
        name = 'winmedic_probe'
        description = '只读采集。set 可选 storage/boot/apps/updates/network/security/recovery/printers/backup/mail/intake/all。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{ set = [ordered]@{ type = 'string'; description = '探针集，默认 storage' } }
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_summary'
        description = '九域体检摘要（含处置建议）。只读。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{ set = [ordered]@{ type = 'string'; description = '指定探针集，缺省用最新采集' } }
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_plan'
        description = '生成处置方案（含分级、证据、建议、planHash）。只读。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{
                set = [ordered]@{ type = 'string' }
                from = [ordered]@{ type = 'string'; description = '指定 findings.json 路径' }
            }
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_apply'
        description = '执行方案中指定的项（默认进隔离区）。写操作；必须 yes=true 且提供 ids。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{
                ids = [ordered]@{ type = 'array'; items = [ordered]@{ type = 'string' }; description = '方案里的 R1/R2 这类 id' }
                yes = [ordered]@{ type = 'boolean'; description = '必须为 true 才会执行' }
                plan = [ordered]@{ type = 'string' }
                acceptRisk = [ordered]@{ type = 'boolean'; description = '恢复能力不足时显式承担风险' }
                action = [ordered]@{ type = 'string'; description = '执行 standalone 动作（如 recovery.create-restore-point）' }
            }
            required = @('yes')
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_verify'
        description = '复核某次执行的效果。只读。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{ journal = [ordered]@{ type = 'string' } }
            required = @('journal')
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_restore'
        description = '把某次执行的隔离项移回原位。写操作；必须 yes=true。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{
                journal = [ordered]@{ type = 'string' }
                item = [ordered]@{ type = 'string'; description = '只恢复指定项' }
                yes = [ordered]@{ type = 'boolean' }
            }
            required = @('journal', 'yes')
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_remote'
        description = '远端只读采集（SSH）。把探针送到远端机器，结果打 origin 标记。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{
                target = [ordered]@{ type = 'string'; description = 'SSH 别名或 user@host' }
                set = [ordered]@{ type = 'string'; description = '探针集，默认 intake' }
                via = [ordered]@{ type = 'string'; description = 'ssh（默认）或 local（loopback 自测）' }
            }
            required = @('target')
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_trend'
        description = '病程：记录快照或查看变化。样本不足时会明确说明，不外推。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{
                record = [ordered]@{ type = 'boolean' }
                set = [ordered]@{ type = 'string' }
                days = [ordered]@{ type = 'integer' }
                top = [ordered]@{ type = 'integer' }
            }
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_diagnose'
        description = '鉴别诊断：给出假设×指标×信号表，不含结论。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{ case = [ordered]@{ type = 'string'; description = '用例 id，如 dx.cdisk-full' } }
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_tools'
        description = '器械台：外部工具可用性与风险级别（只检测，不执行）。'
        inputSchema = [ordered]@{ type = 'object'; properties = [ordered]@{}; additionalProperties = $false }
    },
    [ordered]@{
        name = 'winmedic_journal'
        description = '列出审计批次。只读。'
        inputSchema = [ordered]@{ type = 'object'; properties = [ordered]@{}; additionalProperties = $false }
    },
    [ordered]@{
        name = 'winmedic_explain'
        description = '查看动作的证据、注意事项与回滚方式。只读。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{ action = [ordered]@{ type = 'string' } }
            additionalProperties = $false
        }
    },
    [ordered]@{
        name = 'winmedic_profile'
        description = '查看或维护用户保留项（exclude 通配符）。写操作仅在提供 exclude 时发生。'
        inputSchema = [ordered]@{
            type = 'object'
            properties = [ordered]@{
                exclude = [ordered]@{ type = 'string'; description = '要加入保留项的路径/通配符' }
                remove = [ordered]@{ type = 'boolean'; description = '删除该保留项' }
            }
            additionalProperties = $false
        }
    }
)

$script:WriteTools = @('winmedic_apply', 'winmedic_restore')

function Invoke-Tool {
    param([string]$Name, $Arguments)

    $a = @{}
    if ($Arguments) {
        foreach ($p in $Arguments.PSObject.Properties) { $a[$p.Name] = $p.Value }
    }

    if ($ReadOnly -and ($script:WriteTools -contains $Name -or ($Name -eq 'winmedic_profile' -and $a.ContainsKey('exclude')))) {
        return @{ ok = $false; text = '服务器以 -ReadOnly 启动，写工具被禁用。' }
    }

    switch ($Name) {
        'winmedic_doctor' {
            $r = Invoke-Engine -EngineArgs @('doctor')
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_probe' {
            $set = if ($a.ContainsKey('set') -and $a['set']) { [string]$a['set'] } else { 'storage' }
            $r = Invoke-Engine -EngineArgs @('probe', '--set', $set)
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_summary' {
            $args2 = @('summary')
            if ($a.ContainsKey('set') -and $a['set']) { $args2 += @('--set', [string]$a['set']) }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_plan' {
            $args2 = @('plan')
            if ($a.ContainsKey('set') -and $a['set']) { $args2 += @('--set', [string]$a['set']) }
            if ($a.ContainsKey('from') -and $a['from']) { $args2 += @('--from', [string]$a['from']) }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_apply' {
            if (-not ($a.ContainsKey('yes') -and $a['yes'] -eq $true)) {
                return @{ ok = $false; text = 'apply 必须显式传 yes=true。' }
            }
            $args2 = @('apply')
            if ($a.ContainsKey('plan') -and $a['plan']) { $args2 += @('--plan', [string]$a['plan']) }
            if ($a.ContainsKey('action') -and $a['action']) {
                $args2 += @('--action', [string]$a['action'])
            } else {
                $ids = @()
                if ($a.ContainsKey('ids')) { $ids = @($a['ids']) }
                if ($ids.Count -eq 0) { return @{ ok = $false; text = 'apply 需要 ids 或 action。' } }
                $args2 += @('--ids', ($ids -join ','))
            }
            $args2 += @('--yes')
            if ($a.ContainsKey('acceptRisk') -and $a['acceptRisk']) { $args2 += @('--accept-risk') }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0 -or $r.code -eq 7); text = $r.text }
        }
        'winmedic_verify' {
            if (-not ($a.ContainsKey('journal') -and $a['journal'])) { return @{ ok = $false; text = 'verify 需要 journal。' } }
            $r = Invoke-Engine -EngineArgs @('verify', '--journal', [string]$a['journal'])
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_restore' {
            if (-not ($a.ContainsKey('yes') -and $a['yes'] -eq $true)) { return @{ ok = $false; text = 'restore 必须显式传 yes=true。' } }
            if (-not ($a.ContainsKey('journal') -and $a['journal'])) { return @{ ok = $false; text = 'restore 需要 journal。' } }
            $args2 = @('restore', '--journal', [string]$a['journal'])
            if ($a.ContainsKey('item') -and $a['item']) { $args2 += @('--item', [string]$a['item']) }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_remote' {
            if (-not ($a.ContainsKey('target') -and $a['target'])) { return @{ ok = $false; text = 'remote 需要 target。' } }
            $args2 = @('remote', '--target', [string]$a['target'])
            if ($a.ContainsKey('set') -and $a['set']) { $args2 += @('--set', [string]$a['set']) }
            if ($a.ContainsKey('via') -and $a['via']) { $args2 += @('--via', [string]$a['via']) }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_trend' {
            $args2 = @('trend')
            if ($a.ContainsKey('record') -and $a['record'] -eq $true) { $args2 += @('--record') }
            if ($a.ContainsKey('set') -and $a['set']) { $args2 += @('--set', [string]$a['set']) }
            if ($a.ContainsKey('days')) { $args2 += @('--days', [string]$a['days']) }
            if ($a.ContainsKey('top')) { $args2 += @('--top', [string]$a['top']) }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_diagnose' {
            $args2 = @('diagnose')
            if ($a.ContainsKey('case') -and $a['case']) { $args2 += @('--case', [string]$a['case']) } else { $args2 += @('--list') }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_tools' {
            $r = Invoke-Engine -EngineArgs @('tools')
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_journal' {
            $r = Invoke-Engine -EngineArgs @('journal')
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_explain' {
            $args2 = @('explain')
            if ($a.ContainsKey('action') -and $a['action']) { $args2 += @('--action', [string]$a['action']) }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        'winmedic_profile' {
            $args2 = @('profile')
            if ($a.ContainsKey('exclude') -and $a['exclude']) {
                $args2 += @('--exclude', [string]$a['exclude'])
                if ($a.ContainsKey('remove') -and $a['remove']) { $args2 += @('--remove') }
            }
            $r = Invoke-Engine -EngineArgs $args2
            return @{ ok = ($r.code -eq 0); text = $r.text }
        }
        default { return @{ ok = $false; text = ('未知工具: ' + $Name) } }
    }
}

# ---------------- 主循环 ----------------
Write-Log2 ('started, root=' + $script:Root + ' readonly=' + [bool]$ReadOnly)
while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    $line = $line.TrimStart([char]0xFEFF)
    if (-not $line.Trim()) { continue }
    $msg = $null
    try { $msg = $line | ConvertFrom-Json } catch { Write-Log2 'invalid json'; continue }
    $id = $null
    if ($msg.PSObject.Properties.Name -contains 'id') { $id = $msg.id }
    $method = [string]$msg.method
    if (-not $method) { continue }

    switch ($method) {
        'initialize' {
            Send-Result $id ([ordered]@{
                protocolVersion = '2024-11-05'
                capabilities = [ordered]@{ tools = [ordered]@{} }
                serverInfo = [ordered]@{ name = 'winmedic'; version = $script:Version }
            })
        }
        'notifications/initialized' { }
        'ping' { Send-Result $id ([ordered]@{}) }
        'tools/list' { Send-Result $id ([ordered]@{ tools = $script:Tools }) }
        'tools/call' {
            if (-not ($msg.params -and $msg.params.name)) { Send-Error $id -32602 'missing tool name'; break }
            $name = [string]$msg.params.name
            $known = @($script:Tools | ForEach-Object { $_.name })
            if ($known -notcontains $name) { Send-Error $id -32602 ('unknown tool: ' + $name); break }
            try {
                $res = Invoke-Tool -Name $name -Arguments $msg.params.arguments
                Send-Result $id (New-ToolResult -IsError (-not $res.ok) -Text $res.text)
            } catch {
                Send-Result $id (New-ToolResult -IsError $true -Text ('工具执行异常: ' + $_.Exception.Message))
            }
        }
        default {
            if ($id -ne $null) { Send-Error $id -32601 ('method not found: ' + $method) }
        }
    }
}
Write-Log2 'stdin closed, exit'