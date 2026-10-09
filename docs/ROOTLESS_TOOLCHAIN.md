# RootHide Theos 的 rootless 支持核验

结论：QH 已锁定的 `roothide/theos` 同时提供 roothide 与 rootless scheme，不必为 rootless 换另一套 Theos。核验提交 `88506b2c22e9e07dd4ed055f23c9e398a117a2c7`，不是依据当前 main 猜测。

## 一手证据
- [scheme 选择](https://github.com/roothide/theos/blob/88506b2c22e9e07dd4ed055f23c9e398a117a2c7/makefiles/common.mk)：131–134 行按 `THEOS_PACKAGE_SCHEME` 加载模块，193–194 行选择对应方案库目录。
- [rootless 前缀](https://github.com/roothide/theos/blob/88506b2c22e9e07dd4ed055f23c9e398a117a2c7/vendor/mod/rootless/package.mk)：`THEOS_PACKAGE_INSTALL_PREFIX = /var/jb`。
- [rootless 包架构](https://github.com/roothide/theos/blob/88506b2c22e9e07dd4ed055f23c9e398a117a2c7/vendor/mod/rootless/package/deb.mk)：`iphoneos-arm64`。
- [rootless 链接规则](https://github.com/roothide/theos/blob/88506b2c22e9e07dd4ed055f23c9e398a117a2c7/vendor/mod/rootless/instance/rules.mk)：同时包含 `/var/jb` 和 `@loader_path/.jbroot` rpath，后者不是单独证明混入 RootHide 的信号。
- headers 子模块固定 `ac1c4fd21214548d6d308fcb835d30df1e43953d`；[rootless.h](https://github.com/roothide/headers/blob/ac1c4fd21214548d6d308fcb835d30df1e43953d/rootless.h) 仅在 `THEOS_PACKAGE_SCHEME_ROOTHIDE` 时使用 compat 分支，否则真机走 libroot `JBROOT_PATH_*`。
- lib 子模块固定 `85e9b5b8aff11bbefc59525c64c8f55149926e56`，已核 `iphone/rootless/libroot.a` 存在（25256 bytes）。

## 实际验证与改动
本机 make 执行上述原始 scheme 规则，展开得到 `/var/jb`、`iphoneos-arm64` 和对应 rpath；未编译任何 Apple 二进制。原始文件及结果在 `workspace/qh-rootless-toolchain-check/verification.json`。

撤销候选中按环境换 Theos 的方案，`ci/prepare.py` 现与已交付 native12 逐字节相同。CI 的两种 job 仍独立，通过 QH_SCHEME 对应 THEOS_PACKAGE_SCHEME、ARCHS、头文件/库和维护脚本；不把工具链支持误称 QH 已兼容 rootless。实际 Apple 编译、实包和 rootless 真机验收尚未完成。
