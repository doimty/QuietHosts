# Havoc 上架就绪检查表 · native17 UI 候选

**界面优化不能替代功能/兼容验收。** native17 是 UI 优化候选，不是已上架、已获 Havoc 批准或可收费的 beta；不承诺销量或销售收入。

[项目说明](../README.md)明确 rootless 真机验收仍待完成，且构建通过不等于设备验收。下面是待完成检查，不是对全部实现、许可或兼容性的认证。依据官方公开页面整理；未联系 Havoc 或执行商店发布。

## 1. 明文要求与项目发布门禁

- [ ] **正式版本由人类确认。** Havoc 拒绝含 `debug` 的版本，不允许上传收费 beta（H1 §1.9）。项目另要求正式数字形式版本、通过 release 门禁并在 dpkg 排序上新于已分发候选；这是项目门禁，不能误称 Havoc 禁止所有非数字版本。`FINALPACKAGE=1` 是官方构建建议，不是功能验收（H3）。本轮不选择正式版本或执行支付。
- [ ] **核实包分类。** [源码元数据](../control#L8)已从 `Utilities` 改为 `Applications`，并有源码/实包 Section 校验；两种云端实包都必须通过。Havoc 允许的 Section 仅为 Applications、Development、Tweaks、Themes；还检查 control 必填字段、有效版本与版本顺序（H2）。
- [ ] **英文与真实展示由人类确认。** 用户可见文字必须支持英语；非开发库须有详细、准确的描述和截图。真实截图优先于渲染/生成宣传图，截图不得含个人信息（H1 §1.10、1.18）。逐项核对英文 fallback、功能、限制及真实界面，不用好看的概念图替代实机证据。更新必须有独立且真实的 changelog（H1 §1.8）；不要塞入描述（H4）。
- [ ] **兼容范围只写已证实范围。** 商店 iOS 支持字段必须准确并维护（H1 §1.10.6）。分别验收 rootless / RootHide、设备与依赖组合，不把最低系统版本或模拟器通过写成“全部 iOS15+ 兼容”。收费包两个 major iOS 的兼容更新属于平台期待，文档对私有 API 限制留有例外，不是无条件支持未来版本的承诺（H1 §1.2）。
- [ ] **按 scheme 验实包。** rootless 的 DEB 标签为 `iphoneos-arm64`，RootHide 官方打包模块设为 `iphoneos-arm64e`（T1、T2）；包标签不是 Mach-O CPU slice。分别检查安装布局、资源/链接解析、entitlements、权限与匹配依赖，切换 rootful/rootless 构建前清理（T1）。RootHide 使用动态根与专用 API，不能只改包名或机械替换前缀；其系统 Hosts 镜像涉及符号链接，必须保持项目“不写穿链接”的安全契约（T2）。
- [ ] **支持、授权与隐私文本由人类确认。** 开发者资料至少一个最新有效支持联系方式（H1 §1.1）；不代填私人邮箱。确保代码、图标、截图及任何将来捆绑的规则源具有必要使用/分发/商业授权，并履行第三方许可证义务（H5 §3）。若使用服务处理个人数据，必须有公开易访问且准确的隐私政策（H5 §5）；Havoc 商店隐私政策不代替静域政策。对收集/存储、主动下载、支持资料及可选许可验证分别说明，不能因为没有遥测就写“完全不联网”。
- [ ] **确认修改行为与隐私同意。** Havoc 的 Tweaks 条款要求系统文件修改及退出越狱仍持续的更改取得明确同意；向服务器存储/传送用户数据须明确同意、可删除/下载并在描述披露（H1 §2.4–2.5）。这些条款位于 Tweaks 章节，Applications 的专项适用口径未确认；静域仍以修改前确认、备份、失败拒绝和可验证恢复作为产品安全底线。所需权限必须如实披露（H5 §4）。

## 2. 产品建议与 Sources / DRM 边界

- [ ] **补功能验收证据。** 记录设备 × iOS × bootstrap × 依赖矩阵；验证导入/解析、应用读回、真实解析效果、启停恢复、并发/失败回滚、升级/卸载及不支持环境的安全拒绝。区分静态/模型测试、模拟器 UI 测试和真实设备结果，尤其不能提前勾选 rootless 设备验收。
- [ ] **保留准确状态文案。** 规则数不等于命中/拦截次数；托管文件已验证不等于所有请求被过滤。不得声称全流量保护、百分百广告阻断、虚构实时拦截量或节电收益。
- [ ] **Sources 不强制。** Sources 是可选的手动导入/刷新入口，不是 Havoc 强制要求的模块，也不应把远程源、订阅或外部 API key 设成基本功能门槛（H1 §2.8）。保持项目无内置列表、无后台轮询/定时下载；在线来源只按用户请求更新，文件/粘贴来源为本地快照。不暗示全部来源自动刷新或所有规则语义都被支持。
- [ ] **DRM 不强制。** 收费必须使用 Havoc checkout，但不等于必须添加 DRM。是否实现 DRM 留给人类决策；若采用，另核验官方隐私、安全、合理离线使用及不损害正常付费使用的约束（H1 §1.3、1.17）。基本功能不得依赖用户额外注册自家账户、追加购买或提供 API key，文档另列 DRM/第三方产品例外（H1 §2.8）。
- [ ] **展示与售后准备。** 官方建议 iPhone 纵屏、同类截图规格一致、关闭其他主题/tweak、清晰展示功能和已知问题（H4）。预留及时支持与发布后修复能力。卖家退款说明不得排除 Havoc 全店政策，只可增加更宽松条件（H4、H6）；同包另一软件源托管限制也需人类核对，不能误解为禁止公开源码（H1 §1.7）。

## 3. 未知 / 不应擅自承诺

- 卖家表单完整字段、审核时长、固定截图像素/数量、自定义 depiction schema、RootHide 专项接收规则及本项目实际审查结果，未从所读公开页面确认。
- 真实支持范围、正式版本、英文/截图、支持联系方式、第三方许可清单与隐私政策，仍待人类最终确认。没有确认 Havoc 强制某一种开源许可证、统一 EULA、内置规则源或 DRM。
- 部分官方条款页仍标注 2022 年；正式提交前由人类复核现行规则。公开提交入口不代表账号资格或包已获批准（H7）。本轮只补就绪文档，不发布、不操作账户或支付。

## 官方来源（完整 URL）

- **H1 · Seller Guidelines：** <https://docs.havoc.app/docs/seller/guidelines/>
- **H2 · File Processing Errors：** <https://docs.havoc.app/docs/seller/dashboard/errors/>
- **H3 · Building Your Package Properly：** <https://docs.havoc.app/docs/seller/building_your_package/>
- **H4 · 描述与展示指导：** <https://docs.havoc.app/docs/seller/descriptions/>；<https://docs.havoc.app/docs/seller/presentation/>
- **H5 · Developer Terms：** <https://havoc.app/devtos>
- **H6 · Havoc Refund Policy：** <https://havoc.app/refunds>
- **H7 · Selling on Havoc：** <https://docs.havoc.app/docs/seller/onboard/>
- **T1 · Theos Rootless：** <https://theos.dev/docs/rootless>
- **T2 · RootHide 官方开发文档、打包实现与路径/镜像说明：** <https://raw.githubusercontent.com/roothide/Developer/main/README.md>；<https://raw.githubusercontent.com/roothide/theos/master/vendor/mod/roothide/package/deb.mk>；<https://raw.githubusercontent.com/roothide/Developer/main/roothide.md>；<https://raw.githubusercontent.com/roothide/Developer/main/filemirror.md>
