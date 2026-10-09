# RootHide 官方别名兼容 · 本地修正计划

## 范围与授权
用户要求按原生 RootHide 官方约定放宽识别。在 `qh-roothide-alias-fix` / `fix/roothide-rootfs-alias`（base9b1f72b）实施；随后用户明确“推送构建”，并指出rootless卸载链路也应修改。本阶段允许源码commit/仅此新分支push/GitHubActions双环境验证和失败修复；同步native14版本，并独立纳入两scheme的JSON管道卸载输入修正，详见NATIVE14.md。不安装/设备操作，不改依赖、UI或rootless恢复协议。不声称两份Python报告已经定位真实helper故障。

## 已核依据
固定官方Developer c53cc199f1bab7d7ea2fd70f0a14e215b1f3461b：filemirror.md 明列jbroot `/etc/hosts`镜像；interface.md定义 `jbroot` 把虚拟路径变成系统API物理路径，`rootfs`反向转换；roothide.md说明CLI默认root是jbroot，CLI输入输出均虚拟路径。Bootstrap独立同brand双根拓扑见既有官方bootstrap.m210-225。这支持兼容官方别名，不支持任意目录或取消受保护状态检查。

## 最小实现与假设
- 已有native/canonical白名单保留，额外接受官方rootfs(当前brand派生的固定native路径)。主根回链允许API生成的 `/`，不以用户输入、模糊前缀或硬编码随机brand推导。
- 对已核验的private/var和paired .jbroot链接，仅读打开链接指向的目录，必须与已持有的paired-var/root descriptor在dev/inode/mode/uid/gid上相同。即放宽表示，保持对象身份；不要只凭rootfs返回`/`就接受指向真正系统root的外来回链。
- 初次采集和每次写前既有checkPairedLinks均验证身份；lstat owner/nlink、稳定文字、目录owner/mode以及namespace/事务/备份复核保留。
- 不要求两根同st_dev；比较的是同一目录entry与descriptor。不声称消除检查后TOCTOU。

## 成功标准、独立失败信号与验证
1. C真实隔离软链接：正确目标通过；同权限错误目标、改模式、改owner/dev/ino的expected、dangling、regular均拒绝；删除identity守卫的可执行变异必须被新增错目标断言抓住。
2. Foundation新增别名夹具必须创建真实临时目录别名而非不存在的/rootfs字面路径；API替身仅用于fixture，不操作实际/rootfs。对应exact-brand字面通过，但指向外来同brand对象失败。
3. 原30file及7平台golden保持原SHA，新增可逆投影仅去掉明确唯一的兼容块；非目标旧业务变异仍拒绝；新增块另有C/接线负例。
4. 本机C/Python/cc/clang/UBSan、source/rootless回归和diff；Apple Foundation只待GitHubActions，不能用源码检查冒称运行。

交付边界：这是可审阅的本地兼容候选，不是已消除iOS17故障的真机修复包；若故障在namespace祖先而非链接，此范围可能不够，不顺手删除其他guard。
