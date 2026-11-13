# 更新日志

## v1.1 — 2026-11-13

首个公开发布版本。

### 汉化覆盖

- 主窗口渲染层：DOM 文本、`placeholder`、`title`、`aria-label`、`alt`、`data-tooltip`
- 早期初始化窗口（preload 注入）
- 主进程逐窗口注入（`about:blank` 窗口也生效）
- 菜单栏、窗口标题、原生对话框、系统通知
- 语言声明：`zh-Hans.lproj` + `CFBundleLocalizations`，让系统菜单也跟着中文走
- 词库 2847 条，随构建自动同步

### 运行前检查

界面固定显示三项，**全部通过才能点「开始汉化」**：

1. **已找到 Screen Studio** —— 未找到时给「选择位置…」手动指定
2. **Screen Studio 已启动过** —— 系统要完成注册，权限才可判定
3. **App 管理权限已开启** —— 由引擎实际写一次文件判断，写不进去就是未开启

任一项不通过时，「开始汉化」置灰；提示里会说明具体原因并给出下一步
（去「隐私与安全性 → App 管理」授权，或先去掉下载隔离标记）。

### 关键修复

- **汉化后 App 无法启动**：重签名不再带 `--options runtime`。
  hardened runtime 要求签名锚定受信任的开发者身份，本地自签名证书满足不了，
  系统会以「adhoc signed or signed by an unknown certificate chain」直接拒绝启动。
  只保留 `--deep`（Electron 必须逐层签名，否则 dyld 报 `Library missing`）。
- **「系统不允许修改 Screen Studio」**：多半是 App 带着下载隔离标记，
  提示里直接给出 `xattr -cr` 与授权两种解法，而不是干巴巴报错退出。
- 证书未被信任时自动加入用户级信任，不再静默降级成 ad-hoc。

### 体验

- 汉化结束输出体检：词典条目数 / 注入文件数 / 目标版本
- 版本与词典不一致时给橙色提示，说明新增界面可能仍是英文
- 「运行前检查」标题加大，「重新检查」改为带图标的紫色半透明按钮
- 未安装 Screen Studio 时只保留一条带「选择位置」的提示，不堆无用信息

### 构建

- 词库条数由构建脚本从 `dict.json` 自动写入，不再手写
- 组装与签名改在 `/tmp` 完成后再搬回，避开 Finder 写回 `com.apple.FinderInfo`
  导致的 `resource fork, Finder information, or similar detritus not allowed`
