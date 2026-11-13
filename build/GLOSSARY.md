# Screen Studio 简体中文汉化 — 术语与风格约定

产品：Screen Studio（macOS 屏幕录制 + 自动缩放/光标特效的演示视频工具）。品牌名 "Screen Studio" 保留英文，不翻译。

## 只要遵守的核心规则
1. 输出简体中文；面向 macOS 用户的 UI 文案语气，简洁、专业、不用敬语堆砌。
2. 标签/按钮/菜单项：简短名词或动宾短语，不加句号；如 "Export" → "导出"，"Zoom range" → "缩放区间"。
3. 完整句子保留句末中文句号；原文有省略号 "..." 保留为 "…"。
4. 保留原样不译：Screen Studio、macOS、Pro、URL、LUT、LUTs、H.264、HEVC、PNG、JPEG、SVG、GIF、JSON、FFmpeg、OBS 等专有名词/格式名；键盘键名（Space、Enter、Shift、Cmd、Alt、Backspace、Escape、Tab）译成中文常见写法：Space→空格、Enter→回车、Shift→Shift、Cmd→⌘、Alt→Option、Backspace→退格、Escape→Esc、Tab→Tab。
5. 占位符/变量（如 {count}、%s、{name}）原样保留，不要改。
6. 数字、单位（px、ms、s、MB）原样保留；"1920×1080" 这类保留。
7. 不要意译成营销腔，不要加解释、不要加括号补充说明。
8. 同一概念全批统一用词，见下方术语表。

## 术语表（必须遵守）
- Recording → 录制
- Project → 项目
- Export → 导出
- Timeline → 时间轴
- Slice → 片段（时间轴上切出来的片段）
- Clip → 剪辑
- Zoom → 缩放；Zoom range → 缩放区间；Auto zoom → 自动缩放
- Cursor → 光标；Cursor smoothing → 光标平滑；Click effect → 点击效果
- Camera → 摄像头
- Background → 背景；Background image → 背景图片
- Wallpaper → 壁纸
- Preset → 预设
- Layout → 布局
- Caption / Captions → 字幕
- Transcript → 转写文本
- Audio → 音频；Microphone → 麦克风；System audio → 系统音频
- Mask → 蒙版；Highlight → 高亮
- Shadow → 阴影；Blur → 模糊；Corner radius → 圆角
- Frame → 帧；Frame rate → 帧率
- Motion blur → 动态模糊
- Speed → 速度；Playback → 播放
- Trim → 裁剪；Cut → 剪切；Copy → 复制；Paste → 粘贴；Duplicate → 创建副本；Delete → 删除；Undo → 撤销；Redo → 重做
- Share → 分享；Shareable link → 分享链接；Upload → 上传
- Settings → 设置；Preferences → 偏好设置
- Device → 设备；Display → 显示器；Window → 窗口；Area → 区域
- Shortcut → 快捷键
- Onboarding → 新手引导
- License / Activation → 授权 / 激活
- Workspace → 工作区
- Render → 渲染
- Track → 轨道

## 输出
只输出 JSON，形如 {"translations": {"原文": "译文", ...}}，键必须与输入完全一致（含大小写、标点、首尾空格若输入有）。
