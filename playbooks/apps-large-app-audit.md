# 已安装程序体积审计

## 适用
「装了太多软件」「哪个软件最占空间」「想卸载但不知道卸哪个」。

## Step 1: 枚举并估算体积

```powershell
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
Get-ItemProperty $keys -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -and $_.EstimatedSize } |
  Select DisplayName,DisplayVersion,@{n='MB';e={[math]::Round($_.EstimatedSize/1KB,1)}},InstallLocation |
  Sort-Object MB -Descending | Select-Object -First 30
```

注意：`EstimatedSize` 常常不准（很多安装器不写或写错），**结论要标注「估算」**。

## Step 2: 与磁盘实际占用交叉验证

对 Top 5 的 `InstallLocation` 实测体积；两者差异大时以实测为准。

## Step 3: 分类建议

| 类型 | 建议 |
|---|---|
| 长期不用 | 卸载 |
| 体积大但偶尔用 | 保留，考虑迁移 |
| 运行库/驱动/VC++ | **不要卸载** |
| 系统组件（.NET/WebView2） | **不要卸载** |

## Step 4: 卸载方式

优先走「设置 → 应用」或程序自带卸载器；**不要直接删目录**（会留注册表与服务的烂账）。