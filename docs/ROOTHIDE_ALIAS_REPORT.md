# RootHide 官方别名兼容 · 本地候选结果

## 结论与范围
按用户要求，不再把尚未定位iOS17具体阶段作为拒绝实现官方别名兼容的理由。此候选放宽的是固定路径表示，不是任意目录、文件属主或恢复事务。工作树 `qh-roothide-alias-fix` / `fix/roothide-rootfs-alias`，base9b1f72b。没有commit/push/CI/设备操作；交付native13工作树仍干净。不能称iOS17故障已获真机修复。

## 已实际实现
- 保留native/canonical旧匹配，paired var和primary backlink均可接受官方rootfs(由当前brand独立计算的固定路径)返回的精确别名。主根额外保留realpath别名。
- 新C函数 `QHPairedLinkTargetMatches` 只读打开已核验的固定routing link指向目录，并比较dev/inode/mode/uid/gid与独立持有的paired-var/root anchor。不同文字可以，但不同对象仍拒绝；不会因为`/`在API输出中出现，就接受真的指向系统根的错误回链。
- 初次capture和每次checkPairedLinks均检查对象及链接lstat稳定性，保留原目录/链接owner、nlink、namespace、CAS、journal和备份守卫。链接跟随只用于目录身份的只读检查，写入从不穿透Hosts链接。
- 不改rootless编译分支行为。未放宽配对祖先路径的其他条件；如果真实失败在这些条件，本修正未必足够。

## 回归证据
- 新真实C临时目录/软链接验证：cc和clang通过；同权限外来目标、dev/uid/gid/mode差异、dangling/regular与缺anchor拒绝。
- 删除目标身份条件的两个真实编译/执行变异，在cc/clang分别被新错目标断言拒绝；UBSan通过。
- 4个capture/recheck的接线删除静态负例拒绝；新脚本已接现有scripts/test.py。
- 原30文件Native9及4原UI负例、7平台投影/7旧分支负例通过，旧golden摘要未修改。新模块的guard不是靠冻结投影证明，另由新真实C/变异测试覆盖。
- test_directory_policy --check-baseline、test_regressions、test_native10_ui、validate、diff --check通过。regressions中普通非root权限负例在root host打印SKIP，不计该项通过。
- rootless layout cc/clang302、routing cc/clang281及各3行为变异/UBSan通过；相关输出保存 `workspace/qh-roothide-alias-verification/*-after.json`。
- 新Foundation alias fixture构造真实临时目录别名，并提供同brand文本但指向外来目录的两个拒绝用例。**尚未macOS/Xcode编译或执行**。本机rootless-native明确SKIP77，不计通过。

## 官方来源
已下载固定Developer c53cc199f1bab7d7ea2fd70f0a14e215b1f3461b 的filemirror/interface/roothide/vroot文档至 `workspace/qh-roothide-alias-verification/official/`。文档明确/etc/hosts镜像、rootfs/jbroot互转及CLI虚拟根；不把它们解读为可以取消保护目录或备份验证。

## 剩余验证与后续授权阶段
上述“未commit/Apple运行”记录为本地阶段快照。用户随后已授权推送构建，本轮native14递增版本，并独立纳入RootHide/rootless两份prerm的JSON管道输入，新增完整脚本字节基线校验及生产ReadRequest的macOS测试；详见NATIVE14.md。独立只读审查发现新测试依赖祖先git对象，在浅克隆中会失败；已改为固定基线SHA256，不需要祖先对象，未降低断言。

Apple真实Foundation/生产helper编译、签名与实包审计以本轮Actions实测和交付收据为准，不能在这里预写通过。15/17设备使用和恢复待用户独立验收。保留检查后TOCTOU边界，新增对象核验不是原子namespace锁。不发布native13同版本变体，不把已获RootHide手改卸载反馈扩大为rootless真机已通过。
