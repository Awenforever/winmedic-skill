# Word / Office

## 适用
「Word 一开就报错」「每次启动都要恢复文档」「打字卡」「模板坏了」

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set workloads
```

关注：
- `Normal.dotm`：默认模板，**损坏会导致每次启动异常**（通常 20–50 KB，异常变大就是坏信号）
- `OfficeFileCache`：文档缓存，可清
- Office 加载项（见 `probe.mail-clients` 的加载项列表，Word 加载项在 `HKCU\Software\Microsoft\Office\Word\Addins`）

## Step 2: 按症状分流

| 症状 | 原因 | 处置 |
|---|---|---|
| 一启动就「Word 遇到问题」 | Normal.dotm 损坏 | 重命名后重启 Word |
| 启动慢、卡在加载 | 加载项冲突 | `winword /safe` 验证 |
| 打开大文档卡 | 图形加速/域更新 | 选项 → 高级 → 关闭硬件图形加速；取消自动更新域 |
| 保存报错 | 权限/同步盘冲突 | 另存到本地再迁回 |

## Step 3: 重置模板（可逆）

```powershell
$t = Join-Path $env:APPDATA 'Microsoft\Templates\Normal.dotm'
Rename-Item -LiteralPath $t -NewName 'Normal.dotm.bak' -ErrorAction SilentlyContinue
```

重开 Word 会重建默认模板。**代价**：自定义样式、宏、快速访问工具栏会回到默认。

## Step 4: 安全模式定位加载项

```powershell
Start-Process winword.exe -ArgumentList '/safe'
```

安全模式正常 → 逐个禁用加载项（文件 → 选项 → 加载项 → 管理 COM 加载项）。

## Step 5: 修复安装

设置 → 应用 → Microsoft 365 → 修改 → **快速修复**；无效再**联机修复**（更慢但更彻底）。

## 红线

- 不删整个 `%APPDATA%\Microsoft\Templates`（里面还有别的模板）
- 不删用户文档目录里的 .docx
- 不在 Word 运行时替换 Normal.dotm