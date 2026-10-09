# Rootless 阶段 1：本地适配候选

## 本次授权与基线
用户反馈 native12 已真机测试正常。这里只记录用户反馈，不扩大为独立复测每个恢复/DNS/卸载场景。由 `cee42b76dd96c6699648dd67bdff68f07f708f54` 新建隔离工作树 `feat/rootless-support`。用户随后明确授权“补齐然后提交构建测试”：允许补齐本地测试/文档、commit、仅推此新分支、GitHub Actions 双环境编译及失败修复重跑；不安装、不重启、不发源、不联系 Havoc。依赖仓库只读，不改不重编。

## 已核工具链（用户纠正后复验）
两种 scheme 共用 native12 固定的 RootHide Theos `88506b2c22e9e07dd4ed055f23c9e398a117a2c7` 和 SDK。其 rootless 模块、libroot 头文件/库均已核；无需另换官方 Theos。`ci/prepare.py` 已完整恢复原字节。本机已执行原始 make scheme 展开，未 Apple 编译。详见 `ROOTLESS_TOOLCHAIN.md`。

## 假设及待证事实
- 两种越狱用两份 deb，保持产品 package ID，按 scheme 分别设架构、前缀与依赖。fat Mach-O 不能分派 deb 安装路径，不采用“fat 单包兼容两种 scheme”假设。
- rootless 根与 rootfs 路径以官方 Theos/libroot 契约为准，不用宏把 `jbroot` 机械拼接 `/var/jb`，不沿用 `jbrand` 或 mobile-owned RootHide 路由例外。
- 不把 `pairedDataRoot=nil` 的测试入口直接当生产移植完成。先验证实际根、etc/var拓扑、状态目录保护与 LetMeBlock 读取路径。
- RootHide main/Bridge/FileManager/目录策略、四段事务/回调与30文件SHA是回归基线；必要的路径接线差异用固定可逆patch逐byte复核，不能更新golden掩盖变更。

## 成功标准
1. 环境适配接口给出固定helper、killall、托管Hosts、原始系统Hosts路径；请求不能影响路径选择。
2. rootless 不包含/链接 libroothide，不依赖 jbrand；RootHide 保持原配对根逻辑。
3. 根所有权/目录类型/链接文本/父目录锚点/原始Hosts隔离fail-closed。无法证实布局时拒绝，不泛化符号链接跟随。
4. 路径与scheme门禁有正反例及变异对照；本地不在Apple上执行的部分明确标SKIP。
5. rootless 与 RootHide 独立打包/云门禁，版本 `0.1.0-1+native13` / App build13，避免与native12混用。源码和本机通过后按授权触发云测试，不预写编译或真机成功。

## 独立失败信号及验证
- 任意环境路径、raw Hosts alias、外来链接/可写目录、坏类型可进入写路径 => 失败。
- RootHide冻结差异不能精确逆映射到native12、原套件失败 => 失败。
- 新deb仍依赖 libroothide、缺 libroot/rpath、所有权不为0:0/helper不是4755、架构/前缀不符 => 云/实包门禁失败。
- 未rootless真机验证不能称功能已验收；模拟器UI不证明真机setuid、sandbox、DNS与恢复。

阶段结果写 `ROOTLESS_REPORT.md`，本地测试证据与patch保存在独立候选目录，不污染已交付native12。
