# Native17 · 静域付费产品界面候选

## 范围与边界

- 基线：`52a8252cc50dedfee8f8dddef5ebac90b06e53f6` / native16；独立分支 `feat/havoc-native17-polish`。
- 候选身份：`0.1.0-1+native17`、App build17；两套包仍按 RootHide / rootless 单独构建。
- 目标：改进真实 UIKit 的信息层级、可读性、操作反馈和品牌一致性，不是只改一张宣传图。
- 不是正式商店版本、未联系/提交 Havoc、不设售价或收费；不自动执行设备安装、DNS/Hosts 操作。
- Helper、Shared、Store、Download、真实确认/事务/恢复路径与依赖保持既有安全契约，历史 frozen hashes 不更新。
- 不内置规则源、不定时下载、不加后台驻留/遥测、VPN 或虚构拦截/省电数字。

## 界面改动

### 首页

- 无冗余品牌白卡的轻量 masthead；一个托管状态 hero，真实保存计数与「文件已核验」说明。
- 原生 UISwitch 保持系统尺寸。点击后仍先恢复已核验状态，重新读 helper 状态，再明确确认启用/暂停；不能乐观显示成功。
- 未管理、冲突、读取失败、busy 时禁止启停。未知计数不伪造 0。
- 草稿统计、生成文件大小、授权说明和「预览并应用」在同一个工作区，避免往返滚动。
- 「去除重复条目」是合并时删除的重复数，不是剩余域名，不是广告拦截量。
- 只有本次会话真实的 local/helper revision 都匹配，才能表示已确认应用；同样的数量不能证明相同内容。
- 没有来源且尚无已管理规则时，主操作为「添加第一个规则源」。已管理的空草稿仍保留显式预览/应用，以支持确认清空规则。
- 首次提示只在无来源时展示，可持久收起；帮助随时能在设置查看。

### 规则、设置、弹窗

- 共用紫色动态 palette，白色/石墨表面、细边框、小图标、紧凑指标与清晰分组；大字号时完整换行/单列。
- 来源行不将数值胶囊拉成长条；导航与命令分别使用 disclosure/no-disclosure 行，禁用操作有视觉与 VoiceOver 反馈，触点至少 44pt。
- 手动更新的界面条件与既有事务一致：更新全部 URL 来源，包括未纳入的快照；更新只改变草稿，绝不自动应用。
- 根规则/设置页面的系统大标题、选中 tab 图标与对话框使用同一色板；iPad 采用可读居中列。
- 设置保留实际版本与依赖，补使用指南、隐私/主动网络连接说明和手动浏览器反馈入口；不自动上报资料。
- 短确认仍为居中卡片，输入/多选/长诊断仍是 expanded sheet。选项统一为一个分组，不再每个选项一个巨大卡片。
- 保留先配置真实 modal 属性、text-field hit area、弱引用存活、dismiss 后才调用 handler、重复点击只执行一次的 native16 修复。
- InfoPlist 中英文显示名分别为 QuietHosts / 静域。

## 验证计划与真实状态

本节列方法，不预写 cloud 或实机通过；最终证据见交付收据。

1. `scripts/check_localization.py`：双语键/占位符和真实 QHL 文字覆盖。
2. `scripts/test_ui_palette.py`：从实际使用的共享 tokens 推导明暗文字对比，保留低对比变异拒绝。
3. `scripts/test_native9_ui.py` / `test_native10_ui.py`：业务 frozen 方法、explicit consent、modal/field/dismiss 时序与负例。
4. `scripts/test_native17_ui.py`：新的层级/指标出处/CTA 分组、修订证明、URL 更新条件、命令/导航、引导与隐私。
5. `scripts/test_macho_gate.py`：纯标准库 Mach-O 正反夹具；RootHide arm64e 必须带当前候选所要求的 ptrauth ABI bit。
6. `scripts/test_rootless_package.py` / archive/ownership/entitlement 校验：实际 stage/包身份、0:0、helper4755、minOS、路径/签名结构。
7. `Tests/VisualSmoke.m` / `Tests/DialogSmoke.m`：CI 中真实 UIKit 窗口、320/375/428、明暗、大字及同视图字号往返，真实原生开关、计数/错误状态、截图、键盘/触摸/取消；mock Bridge 的 writes 必须为 0。
8. 真机仍需：触摸、VoiceOver、动态字体、不同语言/系统、已安装数据升级、导入/应用/启停/恢复/卸载与失败回滚。模拟器不证明 helper 权限、Hosts 解析效果或省电。

Windows 只运行可用的 source/portable fixtures，不能拿不支持 setuid 的文件系统去伪造完整 stage 验收，不 monkeypatch 门禁。所有 Apple 编译与 UIKit 执行继续仅用 GitHub Actions。

## 云端产物识别

- 一个 `ui-smoke` job 执行与 scheme 无关的 UIKit 测试，两个 build 都 `needs: ui-smoke`，任何 UI failure 都不被跳过。
- 通过构建后才上传 `quiethosts-native-<scheme>-<run_id>-<attempt>`（deb + build evidence）。失败 job 只上传带 evidence 前缀的证据。
- 另上传 UI screenshot/report 证据；run、attempt、source commit、Xcode、SHA 一起记录。
- 产物：`com.doimty.quiethosts_0.1.0-1+native17_iphoneos-arm64e.deb` / `..._iphoneos-arm64.deb`。
- `Section: Applications`；正式 Havoc 发售需另确认版本/设备证据与 [上架清单](HAVOC_READINESS.md)。漂亮界面不是兼容或销量承诺。

## 首轮云反馈与定位

Run `40975496685` / commit `7b0c1ff` 的源测试、模拟器编译、签名与 bootstatus 通过，但 `simctl launch --console` 在 600 秒后超时，未获得有效进度输出；build 被严格前置门禁跳过。空日志不能证明 App 没启动，也不能把失败归因于 rootless。

审查发现新增主动滚动恢复会对尚未挂载、可能零宽的页面同步 `layoutIfNeeded`。修订改为 pending offset：保留未消费偏移，等 scroll 自身正常布局结束、已挂载且尺寸有效，再先清标志后设置不同的偏移；不再同步排版离屏页。新增负例防止重新引入同步布局或重复覆盖偏移。

测试 App 增加 main/初始化/显示窗口/各布局阶段的 stderr 与 Documents 进度记录；driver 超时仍报失败，但也保留部分 PNG/JSON/进度与仅匹配 `QHVisualSmoke` 的进程采样。600 秒预算、18 组件/108 controller/18 live 字体变更/5 取消/10 截图、原生开关与零写入/零下载等门禁全部保留。修订效果需由后续真实 CI 证据确认，不能以源码推断代替。
