# 卸载残留

> **动手前先看 `plan` 的「已排除」小节**：被排除项要主动交代，被排除 ≠ 不该动。规则见 PB-001。


## 适用
「卸载了还占空间」「软件删不干净」「ProgramData 里一堆陌生目录」。

## Step 1: 确认程序是否真的已卸载

```powershell
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
Get-ItemProperty $keys -ErrorAction SilentlyContinue | Select DisplayName,InstallLocation | Sort-Object DisplayName
```

**注册表里还有条目 = 没卸载干净，走卸载程序；注册表没有 = 可能只是残留目录。**

## Step 2: 残留的典型位置

| 位置 | 内容 | 处理 |
|---|---|---|
| `ProgramData\<厂商>` | 配置/模型/缓存 | 确认程序已卸载后可清 |
| `AppData\Local\<厂商>` | 本地缓存 | 可清 |
| `AppData\Roaming\<厂商>` | 配置，**可能含授权/登录态** | 谨慎，先备份 |
| `Program Files\<厂商>` | 程序本体残留 | 可清 |

## Step 3: 判断能不能删的三问

1. 对应程序还在不在？（注册表 + 开始菜单 + 服务）
2. 目录里有没有用户数据？（.db/.pst/项目文件 → 不能删）
3. 有没有别的程序依赖它？（共享运行库目录 → 不能删）

## Step 4: 执行

纳入 plan 走隔离区，**不要直接 Remove-Item**；确认无误后再 purge。

## 红线

- `Common Files`、`Windows\Installer`、`Microsoft\` 下的共享组件不动
- 名字里带 User Data / Save / Projects 的目录不动