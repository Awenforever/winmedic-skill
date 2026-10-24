# 系统类目标的边界

> 有些目标**不该**用「移走 → 还原」的方式验证，也不该承诺可回滚。本文说明边界与验证方式。

## 三类系统目标

| 目标 | 动作 | 可回滚 | 验证方式 |
|---|---|---|---|
| 回收站 | `storage.recycle-bin-empty` | 是（整目录移入隔离区） | 构造计划后 apply → restore |
| 休眠文件 | `storage.hiberfil-off` | **否**（`powercfg /h off` 直接删除，无法还原内容） | 只做只读探测；执行需用户明确同意 |
| 组件清理 | `storage.winsxs-cleanup` | **否**（DISM 不可逆） | 先建还原点，再考虑执行 |
| 传递优化 / 系统级 WER / Office 缓存 | quarantine 型 | 是 | 与普通目录相同 |

## 为什么休眠文件不可回滚

`powercfg /h off` 会删除 `hiberfil.sys`。再执行 `powercfg /h on` 只会**重新生成**一个空文件，原有内存快照不可能找回。
因此 catalog 中该动作的 `reversible` 必须是 `none`，引擎与文档都不得暗示可以 restore。

## 校验规则

`scripts/validate-catalog.ps1` 会拒绝「command/dism 型动作声明 reversible=full」——这类声明不实会误导用户以为可以撤回。
