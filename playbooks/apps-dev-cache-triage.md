# 开发缓存（npm / pnpm / IDE / 构建产物）

> **动手前先看 `plan` 的「已排除」小节**：被排除项要主动交代，被排除 ≠ 不该动。规则见 PB-001。


## 适用
「node_modules 占满了」「npm 缓存能删吗」「pnpm store 是什么」

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set workloads
```

`workload.dev-caches` 给出 npm 缓存与 pnpm store 体积。

## Step 2: 用包管理器清，不要手删

```powershell
npm cache verify          # 先校验，通常能自动回收一部分
npm cache clean --force   # 彻底清（之后首次安装会变慢）
pnpm store prune          # 只删无引用的包，安全
yarn cache clean          # yarn 用户
```

**手删 `%LOCALAPPDATA%\npm-cache` 也能工作**，但会留下索引不一致；优先用命令。

## Step 3: node_modules 不是缓存

项目里的 `node_modules` 能重装，但：

- 删之前确认 `package-lock.json` / `pnpm-lock.yaml` 在
- 有本地 `file:` 依赖或私有源时，重装可能失败
- 建议按项目清，而不是全局 `del node_modules /s`

## Step 4: 构建产物

| 目录 | 来源 | 说明 |
|---|---|---|
| `dist` / `build` / `out` | 打包产物 | 可删，重新构建 |
| `.next` / `.nuxt` / `.vite` | 框架缓存 | 可删 |
| `target`（Rust/Java） | 编译产物 | 可删，重编慢 |
| `.gradle` / `.m2` | 构建缓存/依赖 | 建议迁移到数据盘，不要随意删 |

## Step 5: 报告

给出「缓存类型 / 体积 / 推荐命令 / 重建代价」。

## 红线

- 不删 `package-lock.json` / `pnpm-lock.yaml`
- 不删 `.git`
- 不在有未提交改动的项目里清构建目录（可能连带清掉未被跟踪的产物）