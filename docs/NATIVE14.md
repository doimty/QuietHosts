# native14 · RootHide别名与双环境卸载输入修正

## 基线与授权
`fix/roothide-rootfs-alias`，base为已交付native13 `9b1f72bf186797819263e8d0491f919a724b5bab`。用户“推送构建”，随后明确指出rootless卸载链路也应修改。只提交源码新分支、双环境云构建/回归与失败修复，不操作手机、安装、重启、发源或上架。测试包 `0.1.0-1+native14` / App build14，dpkg必须高于native13；不是正式发行版本。

## 两个独立行为delta
1. RootHide链接文字除native/canonical旧候选外，允许rootfs(当前brand派生固定路径)的精确别名。只读打开解析后的目录并匹配独立持有的root/paired-var dev/inode/mode/uid/gid；初次capture及每次写前都验证。不同对象、错误品牌、错误属主/权限仍拒绝。详见ROOTHIDE_ALIAS_PLAN/REPORT。
2. 两份prerm都改为 `printf '%s\n' '{}' | <固定helper> restore-for-uninstall`，不再对/dev/null进行poll。RootHide路径 `/usr/libexec/quiethosts-helper`，rootless路径 `/var/jb/usr/libexec/quiethosts-helper`。恢复失败继续exit1，不删state/备份、不忽略错误、不改postrm。RootHide这一输入方式已有用户手动替换后的真机卸载成功反馈；rootless没有独立设备反馈。

## 验证与失败信号
- `test_roothide_alias.py`真实C目录链接/身份正负例、cc/clang删除身份guard变异、UBSan及4接线删除负例。Foundation夹具以真实tempaliases证明allowed文字指向外来同权限目录仍拒绝；实际Foundation执行只在macOS CI。
- `test_uninstall_input.py`与native13脚本逐字比较，只允许输入这一行改变；Linux两scheme16fake-helper案例，确保pipe/空JSON/EOF、错误仍阻止、非卸载分支不调用helper。
- macOS CI额外提取并编译生产 `ReadRequest`、InputLimit和Monotonic函数，在上述两份prerm投影中真实执行16案例；还记录/dev/null对照结果，不假设不同macOS版本必然以相同errno失败。该native输入测试不代替setuid、完整main或恢复/DNS真机测试。
- 原黄金SHA不改。RootHide prerm单行变化精确逆投影；其余业务/UI/rootless冻结及打包30cases/66checks、真实dpkg归档19checks继续执行。
- 云任一job/断言失败、缺helper4755/root数字所有权、架构/路径/签名/版本不符都不得交付。未真机就不称iOS17配对故障已消除。

## 边界
兼容官方映射并不证明先前Python collector已忠实helper namespace；具体17故障阶段仍未获helper现场trace。祖先路径守卫未取消；若问题在该层本版不一定足够。检查与之后系统调用间TOCTOU仍保留。rootless设备验收、真实setuid/沙盒/LetMeBlock读取及DNS未由云测试代替。

## 当前状态
本机语法、16卸载fake案例、对象身份/冻结门禁通过。Apple输入/恢复/生产包待本轮Actions实际结果；不能在此预写成功。交付收据会记录确切source SHA/run/deb SHA和各环境结果。
