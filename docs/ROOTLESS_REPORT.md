# Native13 rootless 候选验证记录

基线 native12 `cee42b76dd96c6699648dd67bdff68f07f708f54`；分支 `feat/rootless-support`；候选版本 `0.1.0-1+native13` / build13。用户授权补齐并提交双环境云测试，不含设备安装、发源或 Havoc 上架。

## 实现与冻结
RootHide/Rootless 共用原固定 Theos/SDK，按 scheme 独立 CPU 架构、链接库、维护脚本与前缀。rootless 使用 libroot 动态根，并校验依赖固定 `/var/jb` 别名；每次事务锚点复查路由证明与持有 fd。严格保护目录属主，不继承 mobile-owned 例外。原 30 文件黄金 SHA 保留，新增 7 文件 native12 基线清单可在浅克隆离线校验。主体 UI、规则引擎、DNS固定命令协议、依赖包不改。

## 本机实际执行
- 原 parser、regressions、directory policy、UI/icon/palette/localization 套件通过。
- rootless layout：cc/clang 各302检查，3有效行为变异拒绝，UBSan通过。
- rootless routing：cc/clang 各281检查，3有效行为变异拒绝，UBSan通过。
- 双环境 synthetic 包夹具：30次真实 validate 调用，66检查通过；含架构/前缀/setuid/minOS/维护脚本/control/错误库/rpath负例。synthetic Mach-O 不证明 Apple 编译或代码签名真实性。
- 7文件原文逆投影和7负例通过，原黄金未更新；diff --check通过。
- Foundation rootless：本机exit77 SKIP，不记PASS。macOS夹具已补 apply/disable/enable/卸载恢复、revision CAS、两处崩溃恢复、写前别名/目录替换及删除路由守卫变异，CI强制真正编译执行。

## 云与设备状态
云流程已接强制双环境门禁，实际结果以本次 GitHub run / SHA / 实包收据为准，本文件不预写成功。用户native12真机正向反馈不等于rootless设备验收。

检查与rename/syscall之间仍存在TOCTOU窗口；write-before-check负例不证明内核级原子拓扑锁。未验证真实setuid/sandbox、依赖DNS读取/重载、rootless卸载或长期行为，不能据云成功宣传全部兼容或省电。
