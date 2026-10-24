# Zotero

## 适用
「Zotero 数据目录很大」「同步一直失败」「换电脑怎么迁」「附件打不开」

## Step 1: 只读取证

```powershell
.\engine\winmedic.ps1 probe --set workloads
```

`workload.zotero`：
- `zotero.sqlite`：**文献数据库**（元数据、笔记、标签）
- `storage\`：**附件本体**（PDF 等），按条目哈希分目录
- `%APPDATA%\Zotero`：配置与插件

> 数据目录位置以 Zotero 设置里的「数据目录」为准；探针默认查 `%USERPROFILE%\Zotero`，若用户改过位置会显示未测。

## Step 2: 体积大怎么办

| 情况 | 做法 |
|---|---|
| 附件多、盘不够 | 设置 → 高级 → 文件和文件夹 → 改数据目录到数据盘（Zotero 会自己搬） |
| 只用 WebDAV 同步 | 仍需要本地 storage，不要删 |
| 想省空间 | 卸载不用的插件、清理回收站（Zotero 里叫「已删除条目」） |

**绝不手删 `storage` 下的哈希目录**——数据库里仍有记录，会变成一堆打不开的断链条目。

## Step 3: 迁移到新电脑（正确顺序）

1. 旧机：Zotero 完全退出
2. 备份**整个数据目录**（`zotero.sqlite` + `storage`）
3. 新机：先装 Zotero，**不要先登录同步**
4. 把备份放到新数据目录位置，启动 Zotero 指向它
5. 确认文献都在，再开同步

**顺序反了会触发同步冲突**，可能丢笔记。

## Step 4: 同步失败常见原因

- 存储配额满（免费账户 300 MB）
- WebDAV 密码/路径错
- 同一账户两处同时改同一库 → 冲突
- 代理拦截（Zotero 走系统代理）

## 红线

- 不删 `storage`、不删 `zotero.sqlite`
- 不在同步进行中强退
- 不把数据目录放进 OneDrive 等实时同步盘（会导致数据库锁冲突）