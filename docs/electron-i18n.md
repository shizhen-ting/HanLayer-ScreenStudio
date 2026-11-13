# 给 Electron 应用做外挂式汉化：不改原程序、随时可回滚

本文以 [Screen Studio](https://screen.studio) 为例，讲怎么给一个成熟的 Electron 应用做界面汉化，
**不修改业务逻辑、不破解授权、不动原安装包**，并且随时能一键还原。

文中的代码都来自本仓库（`engine/`、`build/`、`app-src/`），可以直接对照阅读。

---

## 一、为什么这件事比想象的麻烦

很多人以为汉化 Electron 应用就是「把 `dist/*.js` 里的字符串替换掉」。真做下去会发现文案根本不在一处，
一个成熟的 Electron 应用至少有六个地方在产生界面文字：

| 层级 | 产出什么 | 只改第一层会怎样 |
| --- | --- | --- |
| 渲染进程 DOM | 主体界面文字 | 看起来汉化了 |
| HTML 属性 | 输入框占位符、悬浮提示、无障碍标签 | 输入框还是英文 |
| 动态渲染 | React 每次重绘会写回原文案 | 操作几下就变回英文 |
| preload / 早期窗口 | 启动阶段先渲染的窗口 | 启动瞬间闪英文 |
| 主进程 | 菜单栏、原生对话框、系统通知、窗口标题 | 菜单栏全英文 |
| AppKit | 「窗口平铺」「表情与符号」「听写」等系统菜单项 | 系统级菜单英文 |

所以「汉化完整度」不是态度问题，是**层级覆盖问题**。下面按层拆。

---

## 二、前置：把 asar 打开

Electron 把代码打在 `app.asar` 里。它的格式其实很朴素：

```
[ 8 字节头 ] [ JSON 头（4 字节长度 + JSON）] [ 文件内容按 offset 顺序拼接 ]
```

JSON 头描述一棵目录树，每个文件节点带 `offset` 和 `size`，`offset` 相对于**文件体起点**，不是文件开头。
`unpacked` 为 true 的节点不在 asar 里，实际文件在 `app.asar.unpacked/` 目录下。

**解包**：读 JSON 头，按 offset/size 切片。
**重新打包**：这是容易出错的地方——

- 所有 `offset` 必须**重新计算**，不能沿用旧的
- `unpacked` 文件要跳过，`size` 记为 0
- 目录树顺序要和遍历顺序一致，否则 offset 与内容会错位

本仓库的实现有两份，互相印证：`app-src/Engine.swift`（纯 Swift，约 190 行）和 `engine/asar_tool.py`。

---

## 三、六层注入

核心思路：**不改源码，只在运行时和打包时"叠"一层中文**。每一层都是独立可关的。

### 第 1 层：渲染层 DOM

注入一个 `zh.js`，由 `index.html` 引入。它做三件事：

```js
// 1) 遍历文本节点，命中字典就替换
function translateTextNode(node) {
  const s = node.nodeValue;
  const hit = lookup(s);                 // 精确匹配 + 正则规则
  if (hit && hit !== s) node.nodeValue = hit;
}

// 2) 属性也要处理，否则输入框和悬浮提示还是英文
const ATTRS = ['placeholder', 'title', 'aria-label', 'alt',
               'data-tooltip', 'data-tooltip-content', 'data-tooltip-shortcut'];

// 3) 动态内容：React 每次渲染都会写回原文，必须监听
new MutationObserver(records => { /* 对新增/改动的节点重新翻译 */ })
  .observe(document.documentElement, { childList: true, subtree: true, characterData: true });
```

**关键细节：只能改 `textContent` / `nodeValue`，绝不能改 `innerHTML`。**
动 `innerHTML` 会让 React 的 diff 与实际 DOM 对不上，轻则文本错乱，重则整片组件白屏。

### 第 2 层：preload 末尾

有些窗口在 `index.html` 加载之前就渲染了（启动画面、拖拽区）。在 `preload.js` 末尾追加同一份注入逻辑，
可以覆盖这个阶段。

```js
fs.writeFileSync(preloadPath, origPreload + '\n/* zh-cn preload layer */\n' + prelude + core + '\n');
```

注意这里是**追加**，不是替换——替换会把原有 preload 逻辑冲掉。

### 第 3 层：主进程逐窗口注入

主进程在 `webContents` 创建时统一注入一次。好处是**连 `about:blank` 的窗口也能覆盖**——
这类窗口没有 `index.html`，前两层都够不着。

### 第 4 层：主进程 shim（菜单、对话框、通知）

菜单栏和原生对话框不经过 DOM，只能在主进程里拦。做法是 monkey-patch Electron 的 API：

```js
// 菜单模板在构建时就被翻译
const origBuild = Menu.buildFromTemplate.bind(Menu);
Menu.buildFromTemplate = function (template) {
  return origBuild(translateTemplate(template));
};

// 原生对话框：title / message / detail / buttonLabel 四个字段
for (const k of ['title', 'message', 'detail', 'buttonLabel']) { /* ... */ }
```

菜单项里有一种特殊情况：**`role` 型菜单项**（`about`、`editMenu`、`togglefullscreen`……）。
这类项不写 `label`，文字由系统按 role 生成，改模板没用。要么补 `label`，要么走第 6 层。

### 第 5 层：IPC 载荷递归翻译

右键菜单、录制选项弹层这类原生 UI，文字是主进程发过去的载荷。渲染层收到的已经是一个 JSON 对象，
所以要在 IPC 通道上对载荷做**递归遍历**，翻译其中的 `label`、`submenu`、`title` 等字段。

这一层最容易被漏掉——用户报告「右键菜单还是英文」基本都出在这里。

### 第 6 层：`zh-Hans.lproj` + `CFBundleLocalizations`

AppKit 生成的系统菜单项（窗口平铺、表情与符号、听写、自动填充……）走的是 macOS 本地化机制，
JS 完全够不着。解决办法是给 App 加一个本地化包：

```python
info['CFBundleLocalizations'] = ['en', 'zh-Hans']
os.makedirs(os.path.join(res, 'zh-Hans.lproj'), exist_ok=True)
# 写入 InfoPlist.strings
```

系统在有 `zh-Hans` 且当前语言是中文时，会用中文生成本地化菜单项。

---

## 四、重签名：真正的坑在这里

改完 asar 必须重新签名，否则应用起不来。这一过程中有四个坑，最后一个最难查。

### 坑 1：`ElectronAsarIntegrity` 会让应用直接崩

新版 Electron 在 `Info.plist` 里记录 asar 的哈希。asar 一变，哈希必然失效，应用会拒绝启动。
所以必须删掉：

```bash
/usr/libexec/PlistBuddy -c "Delete :ElectronAsarIntegrity" Info.plist
```

### 坑 2：签名一变，所有权限失效

macOS 的 TCC（隐私权限）认的是**代码签名身份**，不是应用路径。你重新签名后，
系统会把它当成一个新应用——屏幕录制、辅助功能开关虽然还亮着，但实际对不上号，应用依然报"没有权限"。

**解决办法：用固定的本地签名证书，而不是 ad-hoc。**

```python
def ensure_identity():
    """本地自建证书：保证每次重签身份不变，权限只失效一次。"""
    if 证书已存在: return True
    security import ss-zh.p12 -k login.keychain-db -T /usr/bin/codesign
```

ad-hoc（`codesign -s -`）每次签名产生的身份都不稳定，会导致**每次汉化都要重新授权**，
体验极差。自建一张固定证书后，只有第一次需要授权。

### 坑 3：`--deep` 会漏掉嵌套的二进制

`codesign --deep` 在新版 macOS 上已被标记弃用，而且对深层嵌套的处理不完整。
引擎目录里如果有 `.so`、helper 可执行文件，需要递归签名：

```python
for f in find_executables(root):        # 遍历出所有 Mach-O
    run(['codesign', '--force', '--sign', IDENTITY, f])
```

### 坑 4：证书「存在」不等于「能用」

这一条最难查，症状具有很强的误导性：**汉化显示成功，App 却启动即退出**。

根本原因是 `security find-certificate` 只能查到证书是否存在，查不出它是否被系统信任。
一张自签名证书如果没被标记为信任，`codesign` 会拒绝使用它，而脚本往往写了 fallback，
于是一路静默降级成 ad-hoc——对外表现就是"签名成功，但应用起不来"。

自查只需要一条命令：

```bash
security find-identity -v -p codesigning
```

`-v` 表示"只列出有效身份"。如果输出 `0 valid identities found`，而不带 `-v` 时却能列出证书，
那就是这个坑。证书详情里会带 `CSSMERR_TP_NOT_TRUSTED`。

修复不需要管理员密码，加进当前用户的信任设置即可：

```bash
security find-certificate -c "证书名" -p login.keychain-db > /tmp/id.pem
security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/id.pem
```

**为什么 ad-hoc 会失败？** 对开启了 hardened runtime 的应用，ad-hoc 重签后系统会拒绝运行，
而且日志里只有一条完全不相干的报错：

```
ERROR:electron/shell/common/mac/codesign_util.cc:79
task_name_for_pid: (os/kern) failure (5)
```

真正的判决在系统安全模块里：

```bash
log show --last 2m --predicate 'eventMessage CONTAINS "amfid"' | tail
# amfid: /Applications/xxx.app/Contents/MacOS/xxx not valid:
# "The file is adhoc signed or signed by an unknown certificate chain"
```

注意它会**逐个组件报**——主程序、Electron Framework、各个 Helper 全部无效，
这说明是签名链整体不被接受，而不是某个文件漏签。

**经验**：这类环境问题应当在动手改文件**之前**就检查。先跑一遍
`security find-identity -v`，确认有可用身份再开始，比事后从一堆无关日志里反推要省事得多。

---

## 五、安装：权限与用户身份

### App Management 权限

`/Applications` 下的应用受 SIP 保护。普通进程直接改会被拦，弹出「想要修改其他应用」的提示。
两种处理：

- 让用户在「系统设置 → 隐私与安全性 → App 管理」里勾选本程序（之后不再弹密码）
- 或者接受每次输入管理员密码

### 不要用 root 启动 GUI

如果用 `sudo` 提权后直接 `open` 应用，启动的进程属于 `root`，**拿不到当前登录用户的图形会话**，
窗口不会出现，或者出现但权限全空。

正确做法是以控制台用户身份启动：

```python
def open_as_user(app):
    run(['launchctl', 'asuser', str(os.getuid()), 'open', app])
```

---

## 六、可回滚设计

汉化是"外挂"的，所以必须能干净地剥掉。

**首次运行备份原始文件**：

```
~/Library/Application Support/<工具名>/app.asar.4.1.0-5005.orig
~/Library/Application Support/<工具名>/Info.plist.4.1.0-5005.orig
```

备份文件名带版本号，官方更新后旧备份不会被覆盖，回滚仍然指向当初那一版。

**回滚 = 拷回 + 重签名**，不需要联网，也不依赖原安装包。

---

## 七、能不能套用到别的 Electron 应用

可以。这套方法不依赖具体应用，只需要按顺序确认：

1. 找到 `Contents/Resources/app.asar`
2. 解包，看渲染层入口（`dist/index.html` 或等价物）
3. 确认文案字典（可以从界面上抓，也可以从代码里提取）
4. 检查主进程是否用 `Menu` / `dialog` / `Notification`
5. 重打包 → 删 `ElectronAsarIntegrity` → 重签名
6. 测权限（这一步一定要在真机上手动走一遍）

差异主要在于：有些应用会做完整性校验（那就需要额外处理），有些用 Vue 而非 React（MutationObserver 通用）。

---

## 八、踩坑速查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 应用启动即崩 | `ElectronAsarIntegrity` 哈希失效 | 从 Info.plist 删除该键 |
| 操作几下文案变回英文 | React 重绘覆盖 | MutationObserver 重新翻译 |
| 输入框占位符是英文 | 只处理了文本节点 | 处理 `placeholder` 等属性 |
| 菜单栏全英文 | 只做了渲染层 | 主进程 patch `Menu.buildFromTemplate` |
| 右键菜单英文 | 走了 IPC 载荷 | 递归翻译载荷里的 `label` |
| 系统菜单项英文 | AppKit 本地化 | 加 `zh-Hans.lproj` + `CFBundleLocalizations` |
| 每次都要重新授权 | ad-hoc 签名身份不稳定 | 改用固定本地证书 |
| 汉化后打不开 | 签名不完整 | 递归签名所有嵌套可执行文件 |
| 提示要输密码 | 缺少 App Management 权限 | 引导用户勾选，或用管理员权限 |

---

## 结语

外挂式汉化的本质是**在别人的可执行产物上叠一层**，所以它的合法性边界很清楚：

- 分发的应该只是**你自己的那一层**（注入脚本、词典、打包工具）
- 不应包含原应用本体、原始源码或其资源
- 不能绕过授权

做到这三点，它就是一个正当的本地化工具，而不是盗版分发。

本项目完整实现见仓库根目录：`engine/localize.py`（流程）、`build/zh-core.js`（渲染层）、
`build/zh-main.js`（主进程）、`app-src/Engine.swift`（asar）。
