# Steam

## 适用
「Steam 占了几百 G」「游戏装到系统盘了」「着色器缓存越积越多」「游戏打不开要验证文件」

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set workloads
```

`workload.steam` 会区分：
- **cache**：`shadercache` / `appcache` / `depotcache` —— 可清理，代价是首次加载变慢
- **data**：`steamapps\common` —— 游戏本体，**绝不删**

**先看路径在哪块盘**：探针输出的 `items[].path` 前缀就是盘符。系统盘上才需要处理。

## Step 2: 清理缓存（安全）

1. 完全退出 Steam（托盘也要退）
2. 重命名 `steamapps\shadercache` 为 `shadercache.bak`
3. 重开 Steam，进游戏验证正常后再删除 .bak

`appcache` 与 `depotcache` 同理，都是可重建的下载/清单缓存。

## Step 3: 把游戏搬到别的盘（推荐做法）

**用 Steam 自己的库管理**，不要手动剪切：

1. Steam → 设置 → 存储 → 添加驱动器（选目标盘）
2. 选中游戏 → 移动 → 选择目标库
3. 等它自己搬完并校验

手动剪切会导致 Steam 认不出游戏，需要重新下载。

## Step 4: 游戏异常

| 症状 | 处置 |
|---|---|
| 启动闪退 | 右键 → 属性 → 已安装文件 → **验证游戏文件完整性** |
| 卡在更新 | 换下载区域；清 `depotcache` |
| 存档丢失 | Steam 云存档冲突，先看本地 `userdata` 再决定 |

## Step 5: 报告

给出「库在哪个盘 / 缓存多少 / 游戏多少 / 是否需要搬」——只在系统盘紧张时才建议搬。

## 红线

- 不删 `steamapps\common`
- 不删 `userdata`（存档在这里）
- 不在 Steam 运行时移动库