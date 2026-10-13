# native16 · native15 真机 UI 回归修复候选

## 范围与基线

基线 `33190b90e610fb8751879cacc5f9fe34caf1588e`，工作树 `fix/roothide-rootfs-alias`。用户提供真机截图和 12.64 秒录屏，报告弹窗卡顿/忽大忽小，以及 HTTPS 源字段无法输入。本次只修 App 弹窗/输入布局和对应测试，不改 helper、存储、下载、恢复、配对根或已交付 native15 包。用户于 2026-10-13 明确回复“推”：授权提交、仅推本功能分支及双环境 GitHub Actions 验证；不安装、不重启、不发源。新版本 `0.1.0-1+native16` / App build16，避免同版不同字节。

## 已核事实与假设

- 圆角 holder 已设 Auto Layout，但其中 UITextField 未关闭 `translatesAutoresizingMaskIntoConstraints`。字段的真实可见/可点击范围不能由 holder 的外观代替；这是确定的约束接线缺漏，其真机具体 frame 尚未独立采集。
- 居中卡有 1.08 初始 scale，随后在 viewDidAppear 另跑 spring。录屏显示卡片入场先大后小；不能仅凭录屏断言所有卡顿都由此引起。
- 工厂先设置 FormSheet，之后重写 getter 动态报告 OverFullScreen；实际呈现属性及 sheet 配置又在 viewWillAppear 中处理。不同 UIKit 路径是否缓存早期状态未实测。候选把最终样式通过真实 setter 在字段/动作配置期确定，避免入场中修改样式。
- 既有模拟器短确认使用 animated:NO；字段测试仅 becomeFirstResponder/insertText，未检查 bounds 和 window hitTest，故 CI 通过没有覆盖这次回归。

## 最小方案

1. 在 holder 内对 field 关闭 autoresizing-mask 转换，保留 12pt 圆角、左右 12pt 内距和最小 44pt 高度。
2. 删除自定义 scale/spring，仅保留 UIKit CrossDissolve 的淡入淡出，居中卡大小恒定。
3. 动作/字段配置后调用共用 modal 配置，使用真实 presentation/transition setter；居中实例不创建或配置 sheet，viewWillAppear 仅建立布局。保持 eager load 不构建未配置内容、dismiss 后 handler、双击保护及样式冻结。
4. 补模拟器原生测试：两字段真实 bounds、多个文本区触点的 window hitTest、字段切换输入；animated:YES 入场/退场采样 model/presentation transform 与尺寸。保留键盘截图、长文本、大字号、忙碌释放及取消链路。

## 成功标准与独立失败信号

- 两字段拥有非零、>=44pt 高文本区域，左右内距与 holder 一致，文本区命中 field/后代，两者均能获得焦点并插入文字。空范围、命中背景/holder 或字段值不保留均失败。
- 居中确认在 present 前已实际设置 OverFullScreen/CrossDissolve，入退场 card 无缩放且大小稳定；getter-only、任何 scale/spring、转成 sheet 或背景缩放均失败。
- 保持前版居中短确认与长内容 sheet 分流、handler once/dismiss-before-handler、真实 controller 取消/错误忙碌释放。任何原门禁回退均失败。

## 验证与边界

本地执行源码合同及变异、native9 冻结投影、palette、validate、相关回归和 diff 检查。iSH 无 UIKit/Xcode，不做本地 Apple 编译；新模拟器运行证据需 GitHub Actions，真机输入/流畅度仍需复测，不预称已解决。

## 实现阶段本地结果（提交/云结果另记）

- 已落地上述生产修复，仅 `App/QHDialogController.m`；业务调用方、helper、存储/下载等既有生产文件未改。
- `Tests/DialogSmoke.m` 补两字段几何/7 点 window hitTest、切换焦点和两份文字保存；短确认用 animated:YES，真实 setter spy 证明赋值发生在 present 前。入场采样从 present 返回后同步开始，持续到完成回调并取得两个终态显示样本；退场从双击后持续到 handler 与 dismiss 均完成。只校验变换/尺寸，不对淡入 alpha、绝对帧率或耗时设置性能门槛；5 秒是防挂死上限。原键盘截图握手等断言保留。
- 测试用独立小夹具自检空 field/frame 与 1.08 scale 检测器；这不是旧生产源码的原生逆变异执行。原生测试尚未编译/运行，不能计原生通过。
- 模拟器 clang 加 QuartzCore 链接，供 presentation-layer 观察；不是改 App 产品链接。
- 最终本地 `test_native10_ui.py`（12 个源码变异均拒）、`test_native9_ui.py`（冻结范围）、`test_ui_palette.py`（28 对）、`test_regressions.py`、`validate.py` 和 `git diff --check` 全过。当前 UI 门禁对已交付 33190b9 的旧弹窗源码回放明确拒绝（源码证据，不是 UIKit 证据）。
- 日志与录屏帧在 `/var/minis/workspace/qh-native15-device-ui/`。实现完成时 HEAD 仍 33190b9，无新 commit/push/CI；此后按“推”授权将元数据升级为 native16，提交前回归/推送/云结果写独立收据，不以计划代替执行。
- 独审委派没有可用最终报告，不计独审通过。测试子代理已修改测试文件，但最终返回格式不可用，主代理独立读 diff 并修正真实 setter spy 未接工厂、采样只发生于动画结束之后、脆弱 IMP 比较/固定延迟断言及嵌套 runloop 重入；最终依据以文件与本地门禁为准。
