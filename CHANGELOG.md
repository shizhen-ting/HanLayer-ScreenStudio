# 更新日志

## v1.1 — 2026-11-12

首个公开发布版本。

**汉化覆盖**
- 主窗口渲染层：DOM 文本、`placeholder`、`title`、`aria-label`、`alt`、`data-tooltip`
- 早期初始化窗口（preload 注入）
- 主进程逐窗口注入（`about:blank` 窗口也生效）
- 菜单栏、窗口标题、原生对话框、系统通知
- 原生右键菜单、录制选项弹层（IPC 载荷递归翻译）
- AppKit 系统菜单项（`zh-Hans.lproj` + `CFBundleLocalizations`）

**词典**
- 2841 条词条
- 基于 Screen Studio 4.1.0（build 5005）
- 刻意保留英文的：`Screen Studio`、`Unsplash`、`Raycast`、`macOS`、设备型号、音乐曲名、`MP4` / `ProRes` / `GIF` / `FPS` 等专有名词

**安装器**
- DMG 拖拽安装，带背景图
- App 名称为「汉层 HanLayer」，菜单栏、窗口标题、界面标题保持一致
- 图标与界面徽标为「汉层」两字
- 运行前自检：App 是否安装、版本号、「App 管理」权限、权限重置提醒
- 一键回滚到英文原版
- 自动备份原始 `app.asar`
- 内置汉化引擎，无需额外安装 Python
- 下载文件名为 `HanLayer-v1.1-ScreenStudio-4.1.0.dmg`，标出词典对应的官方版本
- 应用菜单（关于 / 服务 / 隐藏 / 退出）与顶部菜单栏改为中文，不再由系统生成英文
- 补充条款同意界面：`I agree to the` / `Privacy Policy` / `and`，共 2846 条

**词典更新**
- 补充激活界面的 `I am a new user` / `I am an existing user` 两条，共 2843 条

**本次修复**
- 签名身份未被信任时自动加入用户级信任（不需要管理员密码），不再直接失败
- 汉化前的环境检查更严格：签名不可用时在改动文件前停止，原 App 不受影响

**已知问题**
- 仅支持 Apple 芯片
- 汉化前请先确认原版能正常打开；原版打不开通常是安装状态不干净，需彻底重装
- Screen Studio 4.1.0 开启 hardened runtime，**ad-hoc 重签后会被系统拒绝启动**，
  需要本机存在受信任的签名身份（详见 README「兼容性」）
- 导出面板与授权界面未逐屏验证
- 个别被 React 拆分的文本节点按片段翻译，读起来可能略生硬
