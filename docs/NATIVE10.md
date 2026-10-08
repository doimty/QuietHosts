# Native10 · 统一弹层与紫色 App 图标

基线42faed7 / native9。用户认可主体页面，只要求统一弹窗风格及更换图标；主体四页结构、来源/白名单语义、Hosts事务与依赖冻结。用户已授权按补测试→提交/推送新分支→云构建/截图后评→审包推进，不包含设备安装/重启/Hosts写入。测试版native10/build10；正式版纯数字政策不变。

设计：采用一套原生导航式sheet，浅紫灰底、白/石墨卡片、紫色图标底块与主操作；确认/恢复/重试/导入/诊断/消息/主题选项/URL输入一致。取消和关闭清晰；危险操作保持红色与完整说明；不重绘系统文件选择器。预览和文本编辑器使用同款sheet chrome。不要把Alert私有子视图强行调色或使用私有API。

行为：统一Dialog action是视觉适配，不改变每个handler/expectedRevision/adoption/状态复查与finishBusy。单次点击防重复；先dismiss再执行旧handler，保持controller到回调结束的生命周期，以免URL输入weak引用失效。禁止手势无回调退出busy确认；显式取消才运行旧cancel handler，不能外点即确认。长文完整可滚动、输入避键盘、Dynamic Type和VoiceOver保留。

图标：原绿色盾牌对勾不再适合紫色；生成闭合平滑白盾牌+三条规则线，紫色轻渐变，无文字无VPN锁，不预剪圆角、不透明RGB。1024/180/120一致比例；保留原型母图和可重现脚本。只改本仓库App图标，不改LMB/libSandy/软件源。

验证：原业务保护区域做类名/工厂名可逆映射后逐字节校验（不是删旧冻结）；固定30文件SHA保留。为Dialog补静态接口/取消/防重复/强生命周期/关闭顺序、负向变异与图标尺寸颜色测试；云端要真实UIKit点选/输入/取消/危险按钮与长文/大字/明暗截图，不能把本地源码测试称Apple编译。新增DialogSmoke六类独立sheet场景及四个真实控制器流程：普通取消/危险确认/选项/实际软件键盘URL输入/长文本辅助大字浅暗模式；导入取消、导入→URL取消、诊断→恢复取消、无效URL→消息关闭。使用主队列与真实UIView/keyboard通知，不通过生产helper，所有write/reload请求计数必须0。单次回调、dismiss时机、weak输入生存、busy释放、工厂loadView时机均独立断言；失败/缺结果/截图不足不得交付。云端结果另记收据，不预写成功。

## Native11 · 点击即展开修复

用户真机图片photo_30FA5D45/photo_8F9C2195显示高级信息/添加来源初始半屏，须手动上滑。源码根因：无输入且detail.length<500无条件medium，漏算选项和中文分段信息。现在默认明确选中large；只对普通Alert、无输入、最多两个action、短且无换行、非辅助大字号采用medium。导入选项/主题选单、输入、分段诊断直接大档位；极长内容仍可滚动，这是展开而非承诺所有文案一屏容纳。

基线78a8677 / native10，包native11/build11，仍同一独立feature分支推进；dpkg必须高于native10。保护业务回调、30个安全文件、主体组件及图标冻结。真实UIKit须检查两个用户反馈入口的初始selectedDetentIdentifier为Large，简单确认仍Medium，并保存首次弹出截图。

补齐此前完整键盘屏幕截图时序：由bounded ready/captured回执握手保持first responder，simctl保存完成才允许关闭；上轮固定等待截图捕到了后续页面，不能声称该图片中键盘可见。保留键盘通知/位置断言，不改150秒总限时，手势/取消/weak引用门禁全部保留。
