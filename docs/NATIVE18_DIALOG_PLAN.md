# Native18 · 弹窗重做规划

> 状态：P1 已通过云端（native18）。随后修复标签切换闪烁并统一弹窗文字块/按钮规格（`0.1.0-1+native19`）。P2 已在本地 `feat/native34-home-dialog-ui` 落地（菜单列表直接贴 sheet、独立取消组、iOS16+ 自定义内容高度 detent / iOS15 medium 回落）。P3 也已在同一分支落地（表单标题进导航栏、正文按段落直接贴 sheet、输入区去卡片化、label 与输入框间距 8pt），并在 CI 烟雾验证通过。P4 也已在同一分支落地：仅草稿保存成功改为底部非阻断提示（`qh.toast`、3 秒消失、不拦截触摸），失败与所有 Hosts 授权/操作结果仍走阻断弹窗。注意：`candidateSources:` 冻结段一直延伸到文件末尾、包含 `commitCandidate:`，所以只改这一处反馈呈现也必须同步刷新 `Tests/Native9Frozen.json` 里该段的摘要；业务逻辑（提交、草稿、修订号、失败文案）未变，`operationCompleted:` 里失败时同名标题仍走阻断弹窗。native17 已交付（[DELIVERY.md](../../deliverables/quiethosts/native17/DELIVERY.md)）。
> 基线：`feat/havoc-native17-polish` / `a64ee6f`；两份 native17 候选包已在云端通过。
> 许可边界：只参考公开开源项目的**交互与排版**，不复制源码。Signal iOS 为 AGPL-3.0-only、Telegram 未核实统一根许可证，均不得进入本 MIT 项目；Wikipedia iOS 为 MIT，仍是"参考"而非搬运。

## 1. 目标与非目标

目标：让弹窗看起来像独立设计过的一层界面，而不是首页卡片加两个大按钮；同时保持"改动 Hosts 必须明确确认"的安全节奏。

非目标：
- 不改 Helper、Shared、Store、Download、事务/恢复/权限逻辑。
- 不引入 FloatingPanel / SwiftMessages / PanModal 等第三方依赖（Swift 库进 Theos-ObjC 双 scheme 包需另行验证，且会扩大冻结面）。
- 不做缩放弹跳入场（native16 已移除，且有明确失败史）。
- 不为了好看弱化任何确认、取消、零写入门禁。

## 2. 现状（代码事实）

| 事实 | 位置 |
|---|---|
| 所有非居中弹窗**只给 largeDetent** | `App/QHDialogController.m:15-21` |
| 居中确认卡片 = 信息行 + 等宽双胶囊按钮 | `App/QHDialogController.m:145-201` |
| 形态判定只看 alert/字段数/动作数/长度 | `App/QHDialogController.m:65-71` |
| 表单类弹窗塞进"卡片套卡片" | `App/QHDialogController.m:229-283` |
| 7 个调用点 | `App/QHAppController.m:338, 669, 779, 821, 1034, 1073, 1411` |

三个具体问题：
1. 短确认复用了首页的信息行与图标块，视觉重量和正文抢空间。
2. 菜单类（主题、添加来源）也是最大高度 sheet，三个选项撑成整屏。
3. 保存成功、错误、授权三类反馈共用同一套结构，节奏单调。

## 3. 三种形态规格

### A · 紧凑确认（Confirm）

用于：一句标题 + 一至两句说明 + 取消/主操作。

- 卡片宽度 `min(320, 屏宽-64)`，圆角 20，内边距 20。
- **去掉左侧图标块**；标题 17pt semibold，正文 15pt regular secondary，行距自然换行。
- 按钮**纵向堆叠、整宽**：主操作在上（填充 50pt 高），取消在下（文字按钮 44pt，不加底色）。
- 危险操作主按钮用 destructive 色，其余用强调色。
- 判定保留：alert、无字段、1–2 个动作、无换行、说明 <500 字符。

> 与现状差异：不再是两颗等宽胶囊，不再有图标块。纵向堆叠对 Dynamic Type 与长中文更稳，视觉也更轻。

### B · 操作菜单（Menu）

用于：跳转式/选择式多选项（主题、添加来源、白名单导入方式）。

- **内容高度**：iOS16+ 用自定义 detent 按内容高度；iOS15 回落 `.medium()`。
- 列表行直接放在 sheet 背景上，**不再套白色大卡片**；行高 52，图标 28pt，分隔线只在行之间。
- 取消独立成一组，位于列表下方，文字按钮。
- 选项不超过 6 个；超出时列表内滚动。

### C · 表单与长内容（Form / Content）

用于：HTTPS 输入、诊断信息、备份说明、首次接管授权。

- 保留 `.large` sheet 与导航栏；标题在导航栏，正文在页面里，不再"标题卡 + 输入卡"。
- 输入区：label 在上、圆角容器内输入框，间距 8；错误提示在字段下方。
- 长文本按段落分组，段间距 12；**主操作固定在内容末尾，不悬浮**。
- 危险操作与关闭按钮分开，关闭在导航栏左侧。

### D · 轻量反馈（Toast，可选，最后做）

"草稿已保存"这类成功反馈改为顶部/底部非阻断提示，3 秒消失；**不替代**任何 Hosts 修改授权与错误提示。

## 4. 场景映射

| # | 调用点 | 场景 | 目标形态 |
|---|---|---|---|
| 1 | `338` | 通用消息（单 OK） | A |
| 2 | `1411` | 恢复基线 / 重新启用 | A（destructive） |
| 3 | `779` | 重试 DNS 重载 | A |
| 4 | `669` | 主题选择 | B |
| 5 | `1034` | 添加来源 / 白名单导入方式 | B |
| 6 | `1073` | HTTPS 来源输入 | C |
| 7 | `821` | 高级信息 / 备份与恢复 | C |

## 5. 形态判定规则（P2 起替换 `QHCenteredConfirmationFor`）

P1 保留现有判定函数：它对本版 7 个调用点给出的结果与新规则完全一致，先只改 A 形态外观，避免同时改动分流逻辑。P2 引入 B 形态时再按下面规则落地并补负例。

按顺序短路，结果参与源码门禁与负例：

1. 有输入字段 → **C**
2. 说明含换行，或长度 ≥500 → **C**
3. 样式为 ActionSheet，或动作数 >3 → **B**
4. 其余 → **A**

规则必须覆盖上表 7 个场景；任何一条改动都要有对应的拒绝变异。

## 6. 实施阶段

### P1 后的闪烁修复与统一（native19）

真机反馈"切换界面闪烁"，根因是页面出现即调用 `refreshStatus`：它先置 busy 并 `render`，而 `render` 会销毁重建全部三页，helper 返回后再重建一次。修复：

- 页面出现与外部变更通知改走 `refreshStatusPassively`：不置 busy、不预渲染、5 秒内不重复请求，且只在状态真正变化时重建。
- 用户主动点「刷新文件状态」仍走原 `refreshStatus`（保留 busy 提示与 `pendingStatus`）。
- 冻结的 `refreshStatus` 与历史方法区间保持字节不变，新方法放在冻结区间之外。

统一：展开式弹窗的标题正文改用与确认框相同的 `QHConfirmTextBlock`，主操作统一用 `QHConfirmButton`（50pt、同字号、同圆角），对话框一律文字优先、不用图标信息行。

| 阶段 | 内容 | 产出 |
|---|---|---|
| P0 | 新建 `feat/native18-dialog-polish`；用现有 DialogSmoke 抓一组"改造前"弹窗截图作为对照 | 基线截图 |
| P1 | 抽出共享 dialog 排版（间距/字号/圆角/按钮），**先把 A 形态重做**，其余形态外观不变 | 可对比的确认框 |
| P2 | B 形态：内容高度 detent + 无卡片列表 + 独立取消 | 主题/添加入口 |
| P3 | C 形态：表单与长内容的页面级排版 | HTTPS 输入、诊断 |
| P4 | （可选）D 轻量反馈 | 保存成功提示 |
| P5 | 云端双 scheme 构建 + 包核验 + 真实截图证据 | native18 候选 |

P1 完成即可审阅方向，不必等 P2/P3。

## 7. 测试与冻结契约

必须**原样保留**（不得借重做放行）：
- `chooseAction:` 的字节冻结（现 `test_native10_ui.py` 的 SHA 断言）。
- 呈现时序：`QHConfigureModal` 先提交 modal 属性；`viewWillAppear` 内不切换呈现属性。
- 输入框 holder 的命中区锚定、弱引用存活、dismiss 后才调用 handler、重复点击只执行一次。
- `QHConfigureModal(nav);` 两处、7 个调用点。
- 无 `CGAffineTransformMakeScale` / 弹簧动画。

需要**替换**（不是删除）的断言：
| 现断言 | 新断言 |
|---|---|
| `centeredCard`、`QHCenteredActionButton` 等内部符号 | 新的确认卡构造与结构标识（如 `qh.dialog.confirm`） |
| 「两个动作共享一行」 | 「动作纵向堆叠、顺序为先取消后主操作或反之，且各占整宽」 |
| 「居中卡片宽 320」 | 保留宽度上限，并新增"无图标块"断言 |
| 菜单「单个 choices 卡片」 | 「列表直接位于 sheet、取消为独立组」 |

`Tests/DialogSmoke.m`（245 项）中的对应语义断言同步改写，数量不减；新增负例覆盖：动作顺序倒置、取消被做成填充按钮、菜单重新套卡片、表单重新套标题卡。

## 8. 视觉验收

- 每个形态至少 3 张真实 UIKit 截图：中文浅色、中文深色、英文或大字号。
- 覆盖：短确认、危险确认、主题菜单、添加来源菜单、HTTPS 输入、长诊断。
- 现有 driver 的 `screenshots` 计数与断言同步调整，不能用旧图充当新形态证据。
- 真机仍需验收：触摸、VoiceOver、键盘、大字号、平板宽度。

## 9. 风险与回滚

| 风险 | 处理 |
|---|---|
| 内容高度 detent 在 iOS15 不可用 | 回落 `.medium()`，不伪造；两端分别截图 |
| 改形态触发既有 smoke 失败 | 按 §7 替换断言并加负例，不删检查、不放宽零写入 |
| 列表滚动手势与 sheet 冲突 | 沿用 `prefersScrollingExpandsWhenScrolledToEdge`，列表内滚动 |
| 视觉回退 | 保留 native17 分支与已交付 deb；native18 独立分支，可整体放弃 |

## 10. 参考对象（仅交互参考）

- [Signal iOS ActionSheetController](https://github.com/SignalApp/Signal-iOS/blob/main/SignalUI/ActionSheets/ActionSheetController.swift)：内容高度、标题/正文层级、取消语义。**AGPL-3.0，只读不复制。**
- [Telegram ActionSheetController](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/Display/Source/ActionSheetController.swift)：动作分组与独立取消区。许可证未核实，只读不复制。
- [Wikipedia iOS](https://github.com/wikimedia/wikipedia-ios)：内容型面板与多步骤组织；MIT。
- Apple `UISheetPresentationController` 文档：detent 与滚动手势行为。
