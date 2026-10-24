# JetBrains IDE（PyCharm / IntelliJ）

## 适用
「PyCharm 越用越慢」「索引卡住」「配置占了几个 G」「重装后设置全没了」

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set workloads
```

`workload.jetbrains` 会列出：
- `caches` / `index` / `log`：**缓存类**，可清理，重建只是首次打开慢
- `%APPDATA%\JetBrains\<产品>`：**配置与插件**，删了设置全丢

## Step 2: 卡顿优先做 IDE 内置操作

**File → Invalidate Caches / Restart** 比手删目录安全得多（会保留设置与插件）。
只有它无效时才动磁盘目录。

## Step 3: 手工清理（关掉 IDE 之后）

```powershell
# 先确认没有 java 进程
Get-Process java,pycharm64,idea64 -ErrorAction SilentlyContinue
# 缓存目录（路径由探针给出）
# 重命名而非删除，便于回滚：
#   caches -> caches.bak
```

## Step 4: 常见坑

| 现象 | 原因 | 处置 |
|---|---|---|
| 索引永远跑不完 | 项目里有巨型目录（node_modules、数据集） | 右键目录 → Mark as Excluded |
| 内存不够 / OOM | 默认堆太小 | Help → Change Memory Settings，改 `-Xmx`（建议物理内存 1/4） |
| 插件导致启动崩溃 | 插件冲突 | 删除 `plugins` 下对应目录 |
| 配置目录巨大 | 历史版本残留 | 旧版本目录可整目录删除（确认新版本正常后） |

## Step 5: 换机器/重装

用 **Settings Sync** 或导出 `File → Manage IDE Settings → Export Settings`。
直接拷 `%APPDATA%\JetBrains` 到新机器常因路径/版本差异出问题。

## 红线

- 不删 `%APPDATA%\JetBrains` 整个目录（那是全部设置）
- 不在 IDE 运行时删 caches
- 不删 `config\plugins` 里付费插件的授权文件