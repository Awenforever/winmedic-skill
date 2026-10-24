# Playbook 路由表

> 按**症状 + 平台 + 触发词**选最具体的一份。只加载命中的 playbook。

| ID | Playbook | 触发示例 | 域 |
|---|---|---|---|
| PB-001 | [cleanup-protocol](playbooks/cleanup-protocol.md) | 任何清理/卸载/删缓存动作的前置协议 | cross |
| PB-101 | [storage-disk-space-recovery](playbooks/storage-disk-space-recovery.md) | C 盘红了、磁盘满了、空间不足、只剩几 G | storage |
| PB-102 | [storage-large-folder-management](playbooks/storage-large-folder-management.md) | 哪个文件夹这么大、大目录治理、想腾空间 | storage |
| PB-104 | [cache-disposal-judgment](playbooks/cache-disposal-judgment.md) | 这个缓存能不能删、删了会怎样、该不该现在动 | storage |
| PB-103 | [storage-partition-audit](playbooks/storage-partition-audit.md) | 分区不合理、C 盘太小、能不能合盘 | storage |
| PB-802 | [setup-backup](playbooks/setup-backup.md) | 怎么备份、有没有备份、备份在哪、能不能恢复 | backup |
| PB-801 | [printer-repair](playbooks/printer-repair.md) | 打印机离线、打印没反应、卡纸、队列卡住 | printers |
| PB-701 | [windows-data-recovery-triage](playbooks/windows-data-recovery-triage.md) | 误删文件怎么找回、回收站清空了、以前的版本 | recovery |
| PB-702 | [boot-failure-triage](playbooks/boot-failure-triage.md) | 蓝屏进不去系统、卡在转圈、自动修复失败 | recovery |
| PB-601 | [endpoint-security-check](playbooks/endpoint-security-check.md) | 帮我看看电脑安全吗、是不是中毒了、防护开没开 | security |
| PB-602 | [bitlocker-recovery-triage](playbooks/bitlocker-recovery-triage.md) | 开机要 BitLocker 恢复密钥、换主板后进不去 | security |
| PB-501 | [network-diagnostics](playbooks/network-diagnostics.md) | 突然断网、能上微信打不开网页、DNS 解析失败 | network |
| PB-502 | [vpn-proxy-troubleshooting](playbooks/vpn-proxy-troubleshooting.md) | 开了代理就上不了网、VPN 连上没网、git 拉不动 | network |
| PB-401 | [update-troubleshooting](playbooks/update-troubleshooting.md) | 更新失败、一直装不上、更新卡住、重启又回滚 | updates |
| PB-402 | [windows-driver-device-triage](playbooks/windows-driver-device-triage.md) | 设备管理器有黄叹号、声卡/网卡失效、驱动装不上 | updates |
| PB-201 | [boot-slow-boot-triage](playbooks/boot-slow-boot-triage.md) | 开机特别慢、开机很久、开机卡住 | boot |
| PB-202 | [boot-startup-bloat](playbooks/boot-startup-bloat.md) | 开机自启太多、启动项、开机弹一堆 | boot |
| PB-203 | [boot-performance-forensics](playbooks/boot-performance-forensics.md) | 电脑卡、CPU 占用高、风扇狂转 | boot |
| PB-301 | [apps-uninstall-residue](playbooks/apps-uninstall-residue.md) | 卸载残留、删不干净、卸载后还在 | apps |
| PB-302 | [apps-migrate-to-another-drive](playbooks/apps-migrate-to-another-drive.md) | 把微信迁到 D 盘、软件搬到别的盘、下载目录搬家 | apps |
| PB-303 | [apps-large-app-audit](playbooks/apps-large-app-audit.md) | 哪个软件占空间、装了太多软件 | apps |
| PB-915 | [differential-cdisk-full](playbooks/differential-cdisk-full.md) | C 盘满：按假设逐条排除，区分治标/治本 | diagnosis |
| PB-913 | [apps-relocate-cache](playbooks/apps-relocate-cache.md) | 想把缓存都搬到非 C 盘、已知文件夹迁移、缺该不该搬 | workloads |
| PB-914 | [apps-adobe-triage](playbooks/apps-adobe-triage.md) | PS 暂存盘已满、Premiere 预览卡、Adobe 缓存 | workloads |
| PB-911 | [apps-sync-clients-triage](playbooks/apps-sync-clients-triage.md) | OneDrive/网盘/会议/播放器缓存能不能删 | workloads |
| PB-912 | [apps-dev-cache-triage](playbooks/apps-dev-cache-triage.md) | npm/pnpm 缓存、node_modules、构建产物 | workloads |
| PB-905 | [apps-latex-triage](playbooks/apps-latex-triage.md) | TeX Live 占空间、宏包找不到、字体缓存坏 | workloads |
| PB-906 | [apps-jetbrains-triage](playbooks/apps-jetbrains-triage.md) | PyCharm 卡、索引重建、IDE 配置占空间 | workloads |
| PB-907 | [apps-steam-triage](playbooks/apps-steam-triage.md) | Steam 占几百 G、游戏装错盘、着色器缓存 | workloads |
| PB-908 | [apps-zotero-triage](playbooks/apps-zotero-triage.md) | Zotero 数据大、同步失败、换机迁移 | workloads |
| PB-909 | [apps-word-triage](playbooks/apps-word-triage.md) | Word 启动报错、模板损坏、加载项冲突 | workloads |
| PB-910 | [apps-proxy-chain](playbooks/apps-proxy-chain.md) | 关了代理反而全断、git/npm 不走代理、多加速器冲突 | workloads |
| PB-903 | [outlook-troubleshooting](playbooks/outlook-troubleshooting.md) | Outlook 打不开、收不到邮件、一直提示配置、加载项冲突 | mail |
| PB-904 | [mail-connectivity-triage](playbooks/mail-connectivity-triage.md) | 邮箱密码对但连不上、发不出去、企业邮箱配置 | mail |
| PB-901 | [windows-new-device-intake](playbooks/windows-new-device-intake.md) | 新机验收、刚买的电脑、帮忙体检 | intake |

## 路由规则

1. **先匹配症状，再匹配平台**；本 Skill 当前只覆盖 Windows。
2. 命中多个时，取**最具体**的（PB-101 优于 PB-102 泛化描述）。
3. 「迁移」类请求 **不得** 路由到清理类 playbook（R3 难例）。
4. 请求含破坏性措辞（全删、直接删、不用备份）→ 强制先走 PB-001。
5. 无匹配时：先用 `winmedic.ps1 doctor` 与只读 probe 收集事实，再决定，不要瞎猜 playbook。

## 域与探针集对应

| 域 | probe --set |
|---|---|
| storage | `storage` |
| boot | `boot` |
| apps | `apps` |
| intake | `intake` |
