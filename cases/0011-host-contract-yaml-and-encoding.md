# 病例 0011：装进 DSH 才暴露的两个「宿主契约」问题

## 1. 症状

- 重启 DSH 后，技能目录里**没有** `winmedic`；调用 `skill` 工具报 `skill "winmedic" is unknown or no longer available`
- 同一时间 MCP 工具能调用，但返回的中文全是乱码：`[*] WinMedic �����Լ�`

## 2. 环境

| 项 | 值 |
|---|---|
| 宿主 | DeepSeek Harness（profile=desktop） |
| 系统 | Windows 11 Pro 26300 / PowerShell 5.1 |
| 安装位置 | `C:\Users\king_\.dsh\skills\winmedic` |
| 引擎 | v1.0.0 → v1.0.1 |

## 3. 采集（证据）

### 3.1 文件在，但技能不在

```powershell
Test-Path C:\Users\king_\.dsh\skills\winmedic\SKILL.md   # True
# 而 DSH 的技能目录里没有 winmedic
```

### 3.2 frontmatter 里出现了裸的「冒号+空格」

```yaml
whenToUse: 用户说 C 盘爆满…… English keywords: remote PC troubleshooting, driver update failed, …
```

按 YAML 规范，未加引号的 plain scalar 里出现 `: ` 会被当作新的键，整个 frontmatter 解析失败。

### 3.3 MCP 输出不是 UTF-8

```
客户端收到:  [*] WinMedic �����Լ�
字节层校验:  以 UTF-8 解码出现替换符（U+FFFD）
```

## 4. 假设与排除

| 假设 | 判据 | 结果 |
|---|---|---|
| 技能目录放错 | DSH 报告的技能根目录就是 `~/.dsh/skills` | 排除 |
| 文件权限问题 | 直接读取 SKILL.md 正常 | 排除 |
| 需要安装器注册 | hermes-butler 只有一个 SKILL.md 也能出现 | 排除 |
| **frontmatter 不是合法 YAML** | 值里含裸 `: ` | **成立** |
| **MCP 端编码与客户端不一致** | 严格 UTF-8 解码失败 | **成立** |

## 5. 处置

| 动作 | 影响面 | 可回滚 |
|---|---|---|
| frontmatter 的 `description`/`whenToUse` 用双引号包裹 | 技能解析 | 是 |
| MCP 启动时设置 `[Console]::OutputEncoding/InputEncoding = UTF8` | 所有 MCP 输出 | 是 |
| 新增 `tests/pester/SkillHost.Tests.ps1`（3 项）：frontmatter 必填、不得有裸冒号空格、MCP 输出严格 UTF-8 且中文可读 | 回归 | — |

## 6. 结果

```
skill  => provider=filesystem  base=C:\Users\king_\.dsh\skills\winmedic
mcp    => {"hasChinese": true, "hasMojibake": false}
tests  => SKILLHOST=3/0
```

- 是否解决：是。重启后技能出现、MCP 中文正常

## 7. 教训

1. **宿主契约是测试的一部分**：frontmatter 的 YAML 合法性、stdio 的编码，都由宿主决定，我们自己的脚本测试覆盖不到
2. **测试里不要自己控制解码**：我之前用管道测 MCP 中文，读取端也是我写的，等于自己给自己判卷；要按宿主的解码方式（严格 UTF-8）来断言
3. **「装进真实宿主」是独立阶段**：单元测试、回归测试全绿，仍可能在宿主侧解析失败——这正是安装测试的价值
4. 新增的 `SkillHost.Tests.ps1` 把这两条契约固定住：以后再改 SKILL.md 或 MCP 输出，CI 会先拦住

## 8. 追加事故：安全软件删文件 + `git add -A` 把「删除」提交进历史

同一轮验证里暴露的第二个问题，比编码问题更危险。

### 现象

v1.0.5 的提交里，`engine/lib/Remote.ps1` 显示 **删除 449 行**：

```
engine/lib/Remote.ps1 | 449 -----------------------------------------
git ls-tree HEAD engine/lib/Remote.ps1   # 空
git ls-tree v1.0.4 engine/lib/Remote.ps1 # 有
```

### 时间线

1. 火绒把**仓库工作区**里的 `Remote.ps1` 删除（读取被拒 → 文件消失）
2. 发版流程里执行 `git add -A`，无差别暂存 → 把「删除」也暂存了
3. `commit` + `tag v1.0.5` 之后才发现

### 影响

- 若直接推送：仓库历史里模块消失，源码不可重现
- 安装包当时仍然完整（`release.ps1` 的兜底从 git 还原了文件，zip 自校验通过）——**这正是最危险的地方：构建成功掩盖了源码损坏**

### 检测

```powershell
git ls-tree HEAD -- engine/lib/Remote.ps1     # 应非空
git show --stat --oneline HEAD                # 看是否有异常删除
```

### 处置

| 动作 | 说明 |
|---|---|
| `git checkout v1.0.4 -- engine/lib/Remote.ps1` | 从历史恢复文件 |
| `release.ps1` 打包前从 `git show HEAD:<path>` 还原缺失文件 | 打包兜底（实测触发） |
| `.githooks/pre-commit` 阻止受保护目录的删除提交 | 实测 `hook exit=1` |
| 仓库目录加入火绒信任区 | 根因处理 |

### 教训

1. **无差别暂存 + 会删文件的外部代理 = 事故**：`git add -A` 在「工作区可能被第三方修改」的环境里不安全
2. **构建成功不等于源码完好**：兜底机制救了安装包，反而掩盖了仓库损坏；发版后应校验关键文件在 `HEAD` 中存在
3. **安全软件的删除是外部事件**：版本管理必须假设工作区随时可能被篡改，而不是假设「文件在就一直在」
