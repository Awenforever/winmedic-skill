# LaTeX / TeX Live

## 适用
「TeX Live 占了几个 G」「编译报错找不到包」「字体缓存坏了」「lualatex 卡在 mktexdb」

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set workloads
```

读 `probe.workloads` 里 `workload.latex`：
- `texmf-var` 是**缓存**（字体图、luatex 缓存），可重建
- `texmf-dist` 是**发行版本体**，删了等于重装，永远不动

## Step 2: 常见症状对照

| 症状 | 原因 | 处置 |
|---|---|---|
| 编译报 `File xxx.sty not found` | 没装宏包 | `tlmgr install xxx` |
| `mktexlsr` / 卡住 | 文件名数据库损坏 | `texhash` 重建 |
| 字体找不到 | 字体映射缓存坏 | 删 `texmf-var\fonts` 后重编 |
| lualatex 首次编译极慢 | lua 缓存被清或未生成 | 正常，第二次会快 |
| 中文断行/乱码 | 引擎或用字不对 | xelatex/lualatex + ctex |

## Step 3: 安全清理（只动缓存）

```powershell
# 先看清体积与路径
.\engine\winmedic.ps1 explain --action storage.winsxs-cleanup  # 仅用于看 cli 用法，别执行
# 手工步骤：
# 1) 关闭所有编辑器与 PDF 预览
# 2) 重命名 texmf-var（不要直接删）
# 3) 重新编译一次文档，让它重建
```

`texmf-var` 位置 = `pdflatex` 所在目录向上退三级再进 `texmf-var`（探针已自动算好）。

## Step 4: 搬家（换盘）

TeX Live 支持整目录搬移，但**必须**重新配置：

1. 整个目录复制到新位置
2. 把新 `bin\windows` 加进 PATH，移除旧的
3. 运行 `tlmgr option repository` 确认仓库可用
4. 用 `kpsewhich article.cls` 验证能找到文件

**不要只改 PATH 不搬目录**，也不要手工改 `texmf.cnf` 里的绝对路径。

## 红线

- 不删 `texmf-dist` / `texmf-local`
- 不删 `tlmgr` 的数据库（会导致包管理器瘫痪）
- 不在有未保存文档时清缓存