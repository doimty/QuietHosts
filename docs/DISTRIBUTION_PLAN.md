# QuietHosts · 发行与依赖说明计划

## 本轮确定的目标
用户要求公开依赖文案不写死测试版本号、不将产品长期定位限定为RootHide，并将已有RootHide LetMeBlock依赖重编为纯数字正式版发布到doimty.github.io。QH后续计划Havoc销售，候选售价$2.99或$3.99，需要考虑rootless用户。

native12 已完成文案/依赖元数据云交付，用户反馈真机测试正常。当前 native13 在 `feat/rootless-support` 补齐 rootless 分支并按新授权进行双环境云编译/回归；不安装、不发源、不上架。native11旧包仍包含旧依赖说明。

推荐公开文字：`所需依赖：LetMeBlock、libSandy。请安装与你的越狱环境匹配的依赖包。` 不固定测试版号。QH control去掉这两个依赖的最低版本文字，但保留包ID和firmware最低iOS。安装“匹配环境的包”不等于任意同名变体兼容：Architecture/签名ABI/读取路径仍必须适配。LetMeBlock自己的libSandy最低版本来自已验证API contract，不能把它随意删掉来证明都兼容。

诊断文字以“当前构建的托管入口由辅助程序校验”描述，保留不透过系统Hosts链接写原文件、备份/恢复/本地URL隐私说明。业务方法只允许已记录的文案片段逆映射，30个安全文件/其他回调逐字节保持。

## Havoc官方已核（2026-10-09查阅）
- https://docs.havoc.app/docs/seller/pricing/ ：$2.99，23%平台费，Seller Proceeds $2.30；$3.99，21%，$3.15。不是税后利润，未核卖家个人结算/汇兑费用；价格尚未选定。
- https://docs.havoc.app/docs/seller/dashboard/errors/ ：rootless iphoneos-arm64文件落于/var/jb；Section只接受Applications/Development/Tweaks/Themes，当前QH Utilities需在正式上架候选修改；旧版/debug/错误目录拒绝。
- https://docs.havoc.app/docs/seller/guidelines/ ：1.9.1付费beta不能上传直至完成；1.17付费用Havoc checkout；1.18必须支持英文；1.7禁止同包双托管（免费+个人源有例外）；1.2期望至少两个major iOS兼容更新，私有API存在实际边界；1.10需真实详细说明与截图；2.5.1系统文件变更需明确同意；2.8首装须有基本功能，不能要求外部注册/API key。
- DRM不是用户请求，本轮不新增授权服务器/联网/付费代码。官方1.3.10若使用API不可将密钥嵌入包。MIT代码可商业发行但版权/许可义务仍保留；不能把原LetMeBlock收费冒充自研。
- 未确认：Havoc同一产品rootless/RootHide两种architecture的具体上传方式、对第三方源依赖是否可自动解决、RootHide arm64e官方接收政策。上架前需向平台核验，不假造“已兼容/必获批”。本轮未登录/提交商品/联系平台。

## Rootless上线前门禁（候选实现中，尚未完整验收）
不直接改scheme就交付，也不让两个环境共用一份不适配deb。建议共享UIKit和规则模型，环境适配分别测试/构建：
1. 已锁定 RootHide Theos 的 rootless scheme/libroot 运行前缀，不需另换工具链；不硬编码随机jbroot或只假设/var/jb必为稳定目录；目标iphoneos-arm64、min15与正确rpath。详见 `docs/ROOTLESS_TOOLCHAIN.md`。
2. Helper当前main的jbrand配对根、AppGroup路径与FileManager双链接/backlink必须设计独立rootless锚点与状态目录，原RootHide安全分支冻结。
3. 核Rootless /etc/hosts与前缀etc/hosts的实际条目/owner/type、外来文件冲突；真实LetMeBlock读取与libSandy授予的路径必须对应。
4. Bridge/helper/killall/uicache/维护脚本各路径和setuid权限、卸载受检恢复、并发/崩溃日志恢复单独负例与真机验证。
5. 双scheme独立目录build，不泄漏兼容shim；arch/minOS/signature/owner/control/依赖/包名实核。Rootless先小列表apply→disable精确恢复→enable，测试真实DNS读取与重载，不只Cloud success。
6. iOS15目标真机中文/英文/明暗/大字/键盘/导入取消/long session与内存验证；不宣传假拦截次数或省电保证。

## 建议发行节奏
先完成免费RootHide依赖正式发布，QH保持测试路线；再做rootless独立适配和真实试用，确认两类用户可用后考虑Havoc付费正式首发。$2.99更适合首发，$3.99应由真实完整兼容和持续维护价值支撑；这是建议，未替用户定价。软件源本轮只发布免费LetMeBlock，不发布付费QH。

## Rootless 移植首阶段（2026-10-09）

用户报告 native12 已在自己的 RootHide 真机测试正常；未逐项提供用例，所以不扩大为全部场景独立验收。已从 cee42b7 创建隔离工作树 `workspace/quiethosts-rootless` / `feat/rootless-support`，原工作树和业务事务层不改。

新增只读目录预检 `Helper/QHRootlessLayout.{c,h}`：root/etc/var/var/lib 均须保护属主与权限，拒绝 raw 系统目录别名、未知链接和 `hosts.lmb` 冲突。`QHRootlessPaths` 将 libroot 动态根与依赖固定别名接入 `QHRootlessRouting` 身份证明；事务初始化、每次锚点/写前守卫均复查证明并核对实际持有 fd。它不是内核事务锁，不承诺消除检查与 syscall 之间的窗口；未知布局 fail closed。

纠正此前草案中的推断：
- rootless 运行根不是固定 `/var/jb`。现代 Theos `rootless.h` 通过 `JBROOT_PATH_*` / libroot 动态获得路径，Dopamine 返回 jailbreak 客户端的真实根。不能把 `jbroot()` 原样带过去或声称其余代码天然兼容。
- 上游 LetMeBlock 的 rootless primary 与 libSandy profile 均写明 `/var/jb/etc/hosts`。后续须把这个受控别名与动态根身份核对，否则“QH 写入的文件”不一定是依赖读到的文件。不能用仅编译成功代替此验证。
- 已核 bootstrap-1800 rootless tar 清单中 `etc`、`var`、`var/lib` 是 root/wheel 0755 真目录，可作为严格 flat 布局夹具的依据；不是对所有 rootless 越狱环境的承诺。
- 传入 pairedDataRoot=nil 只复用旧夹具入口，不能作为安全适配的证据；禁止 RootHide mobile 根例外泄漏到 rootless。
- 同 inode/镜像/恢复守卫保留；未知布局 fail closed，不能删断言求适配。

详见 `docs/ROOTLESS_PLAN.md` 与 `docs/ROOTLESS_TOOLCHAIN.md`。动态根/依赖别名锚定、Bridge/helper/维护脚本路径分支、独立双环境 build/成品门禁已接线；本次补齐测试后按授权提交新分支跑云验证，结果另记真实收据。rootless 真机验收仍是后续独立阶段，未安装、未发源、未上架。

## 打包形态

使用两份环境独立的 deb：RootHide `iphoneos-arm64e` 与 rootless `iphoneos-arm64`，可保持同一 `com.doimty.quiethosts` 包ID，以架构/依赖/安装前缀区分。不因双环境自动更改包ID。fat Mach-O 的 CPU slice 选择不负责 dpkg 安装路径、动态根或依赖分派，不能作为“一份 deb 两环境”的依据。Havoc 的同产品多架构提交政策仍须单独核验。
