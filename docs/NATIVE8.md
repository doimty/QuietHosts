# Native8 · 紫色 UI 测试构建

## 基线、范围与成功标准

基线 `c670053cb53c936f942582bb5ef7f55d55d5b7a9`，native7。独立分支 `fix/purple-ui-native8`；本轮用户授权补齐构建、提交、推送、GitHub Actions 构建交付，不包含安装、重启、Hosts/DNS 操作或 APT 发布。

- 测试包 `0.1.0-1+native8`；App marketing version `0.1.0` / build `8`；CI 包名一致，dpkg 必须高于 native7。
- 紫色主色、浅紫灰背景、明暗卡片与 20pt 圆角。浅色副文字由 `#8B8B96` 加深为 `#686875`。
- 删除未使用的 TileBackground/TileTint，不禁用 `-Werror`。
- 首页唯一域名来自 compiled.domains.count，合并去重来自 compiled.statistics[duplicates]，不硬编码截图数据。规则/设置次级动作改左对齐行，应用仍显式确认。
- Helper、解析器、事务/DNS 行为、依赖及 CC 移除状态保持 native7；不移植 HTML 草图的新主开关、Hero/双格/tile/预览表单，也不把 HTML 演示当作 UIKit 验收。

## 版本规则

测试版允许 `+nativeN` 等英文后缀。正式版本只允许纯数字版本和修订号，例如 `0.1.1-1`。正式交付必须运行 `python3 scripts/validate.py --release`，同步 control、App metadata、CI filename 及候选门禁，并用 dpkg 验证高于已分发的测试版，不能只删除后缀。native8 执行 `--release` 必须拒绝；这不是正式包。

## 验证与独立失败信号

- Portable parser、目录策略、取消生命周期、固定 DNS runner mock、双语资源和 diff 检查。
- 源码提取的 20 组不透明文字/背景对比度至少 4.5:1；旧浅灰文字和未调用配色函数变异必须失败。它不覆盖 disabled/透明度/system控件渲染，更不代替真机可访问性验收。
- 云端 Foundation/mixed UID 隔离测试、实际 arm64e iOS15 App+helper 编译、归档数字 root、helper04755、entitlements、无 CC 及实包/源元数据一致。
- 构建失败、版本不一致、门禁被跳过、未生成 deb、remote SHA 不一致均阻止交付。失败修正必须保留测试和编译警告。

本机无法运行 Apple Foundation/UIKit。手机明暗模式、大字、VoiceOver、长标题、真实操作反馈均尚待验收。云端结果和包哈希以交付收据为准，不在此预写成功。
