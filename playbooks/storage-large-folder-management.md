# 大目录治理

> **动手前先看 `plan` 的「已排除」小节**：被排除项要主动交代，被排除 ≠ 不该动。规则见 PB-001。


## 适用

「哪个文件夹这么大」「想腾空间但不知道从哪下手」「某个目录越涨越大」。

## Step 1: 定位

```powershell
.\engine\winmedic.ps1 probe --set storage
```

读 `findings.json` 中 `probe.top-consumers` 与顶层条目。
没有 WizTree 时该探针较慢（逐目录递归），先告诉用户预计耗时。

## Step 2: 分类，而不是直接删

| 类型 | 特征 | 处理 |
|---|---|---|
| 缓存 | 应用名 + Cache/Code Cache/Service Worker | 可清 |
| 日志 | .log/.etl/dump | 可清，注意排障中不要清 |
| 安装残留 | 卸载后仍在的 ProgramData 目录 | 可清（先确认程序已卸载） |
| 用户数据 | 文档/图片/项目/聊天记录 | **不删，建议迁移** |
| 虚拟机/镜像 | .vhdx/.iso | 建议迁到数据盘 |

## Step 3: 迁移优先于删除

用户数据类，走 PB-302，用官方方式改位置（`SHSetKnownFolderPath` 或应用自带设置），**不要用 junction 绕过**。

## Step 4: 报告

给出「目录 → 类型 → 大小 → 建议动作（清理/迁移/保留）」，不要只列大小。