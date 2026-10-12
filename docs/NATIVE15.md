# native15 · 短确认改为居中紧凑卡片

## 基线与授权
`fix/centered-confirmation-dialogs`，基于 native14 `f748d4cd6f4b35d84f03d28d782e0327b4161016`。用户真机反馈：简短确认（重新启用？/文件操作已完成）不适合半屏底部 sheet（大片空白、取消孤挂左上、确认全宽不对称）。本版只改这类弹窗的呈现形式；未授权安装/设备操作/发源。测试版本 `0.1.0-1+native15` / App build15。

## 行为契约
- 判定（`QHCenteredConfirmationFor`）：`UIAlertControllerStyleAlert`、无文本框、1..2 个动作、正文 <500 字符且无换行。判定在首次呈现时冻结（`resolvedCentered`），之后 actions 清空不会翻转样式。
- 呈现：`modalPresentationStyle=OverFullScreen` + `crossDissolve`，隐藏导航栏；`QHConfigureModal` 对居中实例不再强制 formSheet，对其它 controller（preview/editor nav）行为不变。
- 布局：黑 45% 调光背景；`QHVCard` 居中卡片，宽 `min(320, 屏宽-64)`；图标+标题+正文卡；单动作全宽主色按钮；两动作横排同行——取消浅色（左）、确认紫/红（右），高 ≥46；卡片置于可滚动画布并带上下边界不等式，大字号不产生约束冲突。
- 动画：仅 `animated:YES` 呈现时做 1.08→1.0 弹簧缩放；Reduce Motion 或无动画呈现直接终态（CI 截图稳定）。dismiss 后通过 `crossDissolve` 反向淡出。
- 不变：选项（ActionSheet）、诊断/备份（含换行长文）、URL/导入（含字段）仍为原 sheet；`chooseAction` 防重入、`modalInPresentation`、handler 时序、恢复/CAS/备份协议、native14 全部修复。

## 测试
- `Tests/DialogSmoke.m`：stage0/1 断言居中形态（非 sheet、无导航栏、取消先于确认、两动作同排）；stage2+ 保留 grabber/large 断言；长文本滚动可达、键盘流程、真实 controller 流程全保留。
- `scripts/test_native10_ui.py`：居中结构断言（OverFullScreen/crossDissolve/buildCenteredConfirmation/navigationBarHidden/判定函数）+ 6 个拒绝性变异（含改回 PageSheet、删除居中调用）+ 冒烟文案锁。
- 本地已过：native9/10/ui_palette/回归/validate/diff --check。UIKit 真实渲染、键盘、截图与成品包审计只在本轮 GitHub Actions 验证；真机效果待用户实测。

## 边界
云通过不等于真机视觉验收；用户对居中形态的最终审美判断以真机截图为准。sheet 模式（长内容）保留既有左上角取消位置，本版不重排。没有设备操作。
