# Native22 · 重启后规则被系统还原的恢复

## 现象与根因

真机重启后首页报「文件状态冲突 / target-conflict」。只读证据：`/etc/hosts` 又变回符号链接（bootstrap 原始镜像，mtime 仍是镜像构建日期）。

RootHide 启动时会把 `/etc` 重新镜像回 bootstrap 原始快照。我们应用规则时是把该目录项原子替换成普通文件（必须如此，否则会写穿链接），重启后镜像重建，目录项回到原始状态。

`Helper/QHFileManager.m` 在 `load` 阶段比对「当前目录项」与 `state.target`，类型不符即 `target-conflict` 并拒绝一切写入。这是 fail-closed，但结果是：规则失效、数据仍在、应用内没有任何出口。

## 改动

只在 helper 里增加一种**已知的、非篡改**情形：

| 当前目录项 | 判定 | 行为 |
|---|---|---|
| 等于 `state.target` | 正常 | 不变 |
| 等于 `state.original` 且 `state.active` 为真 | **重启还原** | 状态报 `inactive` + `reverted:YES`，允许重新 apply |
| 其他 | 冲突 | 继续 `target-conflict` |

实现要点：

- `QHTransaction.targetReverted` 仅在上述第二种情形置位；其余路径不变。
- `transact:` 的「已 active 且快照相同则跳过」增加 `&& !targetReverted`，否则重新应用会假成功而不写盘。
- `response` 在还原时把 state 报为 `inactive`（文件真相），并附 `reverted:YES`；**持久化状态不在此写入**。
- `state.original` 保持不变，因此之后 `disable` 仍能恢复真正的原始镜像。

## 冻结基线更新（唯一一次，已获用户确认）

`Helper/QHFileManager.m` 在 `Tests/Native9Frozen.json` 与 `Tests/RootHidePlatformFrozen.json` 中是字节冻结基线。本次改动无法绕开，两个清单中该文件的摘要同步刷新：

- 旧：`e1a6a1555b9420785f7facfb2c3ba0eb7514dbf7dfb19eeaf04a6394d9695d6e`
- 新：`6da5927a1d9ea747943b34546961d8f35a24820dd867f05474c90962837e8901`

其余 6 个受冻结文件未变。`test_platform_freeze.py` 仍验证投影一致性与 7 个变异拒绝；其输出文案改为「与已审阅清单一致」，不再声称哈希未变。

## 界面

- 还原时首页标题为「重启后规则已被还原」，状态胶囊为「未应用」，说明写清是系统重建镜像、已保存规则未生效。
- 启停仍不可用（没有可切换的 active 状态）；主操作恢复为可用的「预览并应用」，走原有确认流程重新接管。

## 测试

- `Tests/FileManagerTests.m` 新增 `RevertedAtBoot()`：还原后 status 报 inactive + reverted（不报冲突）→ apply 真正重写（`changed` 为真、内容为新规则）→ disable 仍恢复真正原始内容。
- 同一夹具同时验证**外来内容仍是 target-conflict 且不被改写**。
- 既有 mount-identity、metadata-strict、journal 等用例保留。

## 边界

- 本版只处理「目录项回到我们记录的原始状态」。若重启后文件被第三个程序改过，仍会拒绝，这是设计。
- 模拟器/CI 不覆盖真实 RootHide 重启镜像行为；真机验证仍未做。
- 未新增 helper 命令，`main.m` 命令表不变。
