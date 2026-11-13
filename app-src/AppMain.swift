import SwiftUI
import AppKit

enum DictInfo {
    /// 词典对应的 Screen Studio 版本
    static let target = "4.1.0"
    /// 词典条目数，随每次发版更新
    static let entries = 2847
}

struct Check: Identifiable {
    let id = UUID()
    var ok: Bool
    /// 中性提示（灰蓝色），用于「暂时无法判断」的状态
    var info: Bool = false
    var title: String
    var detail: String
    var action: (() -> Void)? = nil
    var actionTitle: String = ""
}

final class Runner: ObservableObject {
    @Published var running = false
    @Published var status = "准备就绪：点「开始汉化」即可"
    /// 所有前置条件是否满足，不满足则禁用汉化/还原按钮
    @Published var ready = false
    @Published var log = ""
    @Published var checks: [Check] = []
    @Published var appVersion = ""
    @Published var progress: Double? = nil
    @Published var customPath: String? = nil

    let logURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/SSHanHua.log")

    var ssPath: String? {
        if let c = customPath { return c }
        return ["/Applications/Screen Studio.app",
                NSHomeDirectory() + "/Applications/Screen Studio.app"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    func appendFile(_ s: String) {
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(s.data(using: .utf8)!); try? h.close()
        }
    }

    /// 本地是否留有可回滚的备份（「恢复英文原版」只依赖它，与能否开始汉化无关）
    @Published var hasBackup = false
    /// 内置引擎是否缺失（工具被不完整拷贝时会发生）
    @Published var engineMissing = false

    func refreshBackup() {
        let dir = NSHomeDirectory() + "/Library/Application Support/Screen Studio 汉化"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        hasBackup = files.contains { $0.hasSuffix(".orig") }
    }

    func refreshChecks() {
        var list: [Check] = []
        refreshBackup()

        let engine = Bundle.main.bundlePath + "/Contents/Resources/engine/sszh-engine"
        engineMissing = !FileManager.default.isExecutableFile(atPath: engine)
        if engineMissing {
            ready = false
            list.append(Check(ok: false,
                              title: "工具文件不完整",
                              detail: "内置汉化引擎缺失，可能是拷贝时少了文件。请重新下载安装包，把整个 App 拖进「应用程序」",
                              action: { NSWorkspace.shared.open(URL(string: "https://github.com/shizhen-ting/HanLayer-ScreenStudio/releases/latest")!) },
                              actionTitle: "重新下载"))
            checks = list
            status = "还不能开始：工具文件不完整，请重新下载"
            return
        }

        // ① 是否安装
        if let app = ssPath {
            let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")
            appVersion = info?["CFBundleShortVersionString"] as? String ?? "未知版本"
            let base = appVersion.split(separator: "-").first.map(String.init) ?? appVersion
            let matched = (base == DictInfo.target)
            list.append(Check(ok: true, title: "已找到 Screen Studio",
                              detail: matched
                                ? "\(appVersion) · 词典 \(DictInfo.entries) 条，版本匹配"
                                : "\(appVersion) · 词典针对 \(DictInfo.target)",
                              action: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app)]) },
                              actionTitle: "在访达中显示"))
            if !matched {
                list.append(Check(ok: false,
                                  title: "版本与词典不一致",
                                  detail: "汉化仍可用，但 Screen Studio \(base) 与词典的 \(DictInfo.target) 不同，新增或改动的界面可能仍是英文",
                                  action: { NSWorkspace.shared.open(URL(string: "https://screen.studio")!) },
                                  actionTitle: "查看官网"))
            }

            // ② 是否启动过（启动后系统保护才生效，权限判断才有意义）
            let ranBefore = hasRunBefore(app)
            if ranBefore {
                list.append(Check(ok: true,
                                  title: "Screen Studio 已启动过",
                                  detail: "系统已完成注册，可以判断权限状态",
                                  action: { NSWorkspace.shared.open(URL(fileURLWithPath: app)) },
                                  actionTitle: "打开"))
            } else {
                list.append(Check(ok: false,
                                  title: "Screen Studio 还没启动过",
                                  detail: "先双击打开一次它，系统完成注册后再点「重新检查」",
                                  action: { NSWorkspace.shared.open(URL(fileURLWithPath: app)) },
                                  actionTitle: "打开一次"))
            }

            // ③ 能否改写（App 管理权限）
            let writable = probeWritable(app)
            let quarantined = hasQuarantine(app)
            if ranBefore && writable {
                list.append(Check(ok: true,
                                  title: "App 管理权限已开启",
                                  detail: "可以直接改写 Screen Studio，不会弹密码",
                                  action: { self.openAppManagement() },
                                  actionTitle: "打开设置"))
            } else {
                let why: String
                if !ranBefore {
                    why = "Screen Studio 启动过之后才能确认，先完成上面第二项"
                } else if quarantined {
                    why = "带有下载隔离标记：先执行 xattr -cr 去掉，或到「隐私与安全性 → App 管理」授权本程序"
                } else {
                    why = "到「隐私与安全性 → App 管理」把「汉层 HanLayer」打开，再点「重新检查」"
                }
                list.append(Check(ok: false,
                                  title: "App 管理权限未开启",
                                  detail: why,
                                  action: { self.openAppManagement() },
                                  actionTitle: "打开设置"))
            }
            ready = ranBefore && writable
        } else {
            ready = false
            list.append(Check(ok: false, title: "没找到 Screen Studio",
                              detail: "默认找「应用程序」文件夹；装在别处就手动选，没装过就去官网下载",
                              action: { self.pickApp() },
                              actionTitle: "选择位置…"))
            list.append(Check(ok: false,
                              title: "Screen Studio 还没启动过",
                              detail: "装好并打开一次之后再检查",
                              action: { NSWorkspace.shared.open(URL(string: "https://screen.studio")!) },
                              actionTitle: "去官网"))
            list.append(Check(ok: false,
                              title: "App 管理权限未开启",
                              detail: "装好 Screen Studio 后会自动检测；也可以先到「隐私与安全性 → App 管理」把本程序打开",
                              action: { self.openAppManagement() },
                              actionTitle: "打开设置"))
        }
        checks = list
        if !running {
            status = ready ? "准备就绪：点「开始汉化」即可"
                           : "还不能开始：请先完成上面标黄的检查项"
        }
    }

    func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "选择 Screen Studio.app"
        if panel.runModal() == .OK, let u = panel.url {
            var p = u.path
            if p.hasSuffix("/Contents/MacOS/Screen Studio") {
                p = String(p.dropLast("/Contents/MacOS/Screen Studio".count))
            }
            customPath = p
            refreshChecks()
        }
    }

    /// 检测能否改写 Screen Studio。
    ///
    /// 关键：必须让**引擎自己**去测。引擎在真正汉化时由本 App 启动，
    /// 与 Swift 进程同属一个 TCC 归属；用 Swift 直接写文件测出的结果可能与实际不符。
    func probeWritable(_ app: String) -> Bool {
        let engine = Bundle.main.bundlePath + "/Contents/Resources/engine/sszh-engine"
        guard FileManager.default.isExecutableFile(atPath: engine) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: engine)
        p.arguments = ["--check", app]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 判断 App 是否启动过。
    ///
    /// 刚拷进 /Applications、从未打开过的 App，macOS 还没完成注册，
    /// 「App 管理」保护尚未生效——此时写入测试会错误地通过。
    /// 用「是否留下偏好设置或应用数据」来判断是否已经跑过一次。
    func hasRunBefore(_ app: String) -> Bool {
        // 用系统记录的「最近使用时间」判断这一份拷贝有没有被打开过。
        // 它随每次启动更新，且重装 App 后会重置——比看偏好设置文件可靠
        // （偏好设置卸载后不会删除，会让人误以为启动过）。
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        p.arguments = ["-raw", "-name", "kMDItemLastUsedDate", app]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        let out = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty || out == "(null)" || out == "null" { return false }
        return true
    }

    /// 检查 App 是否带下载隔离标记（从浏览器下载的 zip 解压出来就会有）
    func hasQuarantine(_ app: String) -> Bool {
        let paths = [app, app + "/Contents/Resources/app.asar", app + "/Contents/MacOS"]
        for p in paths where getxattr(p, "com.apple.quarantine", nil, 0, 0, 0) > 0 {
            return true
        }
        return false
    }

    func pythonWorks() -> Bool {
        guard FileManager.default.fileExists(atPath: "/usr/bin/python3") else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", "print(1)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        let deadline = Date().addingTimeInterval(6)
        while p.isRunning && Date() < deadline { usleep(100_000) }
        if p.isRunning { p.terminate(); return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.contains("1") == true
    }

    func openPane(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    func openAppManagement() {
        for s in ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles",
                  "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"] {
            if let u = URL(string: s), NSWorkspace.shared.open(u) { return }
        }
    }

    func appRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "MacOS/Screen Studio"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func start() {
        guard !running, let app = ssPath else { return }
        refreshChecks()

        if appRunning() {
            let a = NSAlert()
            a.messageText = "Screen Studio 正在运行"
            a.informativeText = "汉化过程中需要关闭它再重新打开。\n如果里面有没保存的项目，请先回去保存，再点「继续」。"
            a.addButton(withTitle: "继续")
            a.addButton(withTitle: "取消")
            if a.runModal() != .alertFirstButtonReturn { return }
        }

        runEngine([app], restoreMode: false)
    }

    func restore() {
        guard !running, let app = ssPath else { return }
        let a = NSAlert()
        a.messageText = "恢复英文原版？"
        a.informativeText = "会用备份把 Screen Studio 恢复到汉化前的样子。"
        a.addButton(withTitle: "恢复")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        runEngine(["--restore", app], restoreMode: true)
    }

    func runEngine(_ args: [String], restoreMode: Bool) {
        running = true
        progress = restoreMode ? nil : 0
        status = restoreMode ? "正在恢复原版…" : "正在汉化…"
        log = ""
        try? "".write(to: logURL, atomically: true, encoding: .utf8)

        let engine = (Bundle.main.resourcePath ?? "") + "/engine/sszh-engine"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: engine)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ELECTRON_RUN_AS_NODE")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            self.appendFile(s)
            DispatchQueue.main.async {
                self.log += s
                for line in s.split(separator: "\n") {
                    let t = String(line)
                    if let r = t.range(of: "步骤 ") {
                        let num = t[r.upperBound...].prefix(while: { $0.isNumber })
                        if let n = Double(num) { self.progress = min(1, n / 9.0) }
                    }
                    self.status = t
                }
            }
        }
        p.terminationHandler = { proc in
            DispatchQueue.main.async {
                self.running = false
                self.progress = nil
                pipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    self.refreshChecks()
                    self.finish(restoreMode)
                } else if self.log.contains("需要管理员权限") {
                    self.adminRun(args, restoreMode: restoreMode)
                } else {
                    self.status = "失败（退出码 \(proc.terminationStatus)）"
                    let a = NSAlert()
                    a.messageText = "操作失败"
                    a.informativeText = "可以点「查看日志」看详细信息，或把日志发给维护者。"
                    a.addButton(withTitle: "查看日志")
                    a.addButton(withTitle: "关闭")
                    if a.runModal() == .alertFirstButtonReturn { self.openLog() }
                }
            }
        }
        do { try p.run() } catch {
            running = false
            status = "无法启动 Python 引擎"
        }
    }

    func finish(_ restoreMode: Bool) {
        status = restoreMode ? "完成：已恢复英文原版" : "完成：界面已恢复简体中文"
        let a = NSAlert()
        a.messageText = restoreMode ? "已恢复英文原版" : "汉化完成"
        a.informativeText = restoreMode
            ? "Screen Studio 已重新打开。"
            : "Screen Studio 已重新打开，界面是简体中文。\n如果它提示要屏幕录制/辅助功能权限，点允许即可。"
        a.addButton(withTitle: restoreMode ? "好" : "打开 Screen Studio")
        if !restoreMode {
            a.addButton(withTitle: "去授权屏幕录制")
            a.addButton(withTitle: "完成")
        }
        let r = a.runModal()
        if !restoreMode {
            if r == .alertFirstButtonReturn, let app = ssPath { NSWorkspace.shared.open(URL(fileURLWithPath: app)) }
            if r == .alertSecondButtonReturn { openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") }
        }
    }

    func adminRun(_ args: [String], restoreMode: Bool) {
        let engine = (Bundle.main.resourcePath ?? "") + "/engine/sszh-engine"
        let scriptPath = NSTemporaryDirectory() + "ss-zh-admin.sh"
        let body = "#!/bin/bash\n" + shq(engine) + " " + args.map(shq).joined(separator: " ") + " 2>&1\n"
        try? body.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "do shell script \"/bin/bash " + scriptPath + "\" with administrator privileges"]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        p.terminationHandler = { proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            self.appendFile(out)
            DispatchQueue.main.async {
                self.running = false
                self.progress = nil
                self.log += out
                for line in out.split(separator: "\n") {
                    let t = String(line)
                    if let r = t.range(of: "步骤 ") {
                        let num = t[r.upperBound...].prefix(while: { $0.isNumber })
                        if let n = Double(num) { self.progress = min(1, n / 9.0) }
                    }
                }
                if proc.terminationStatus == 0 && out.contains("完成") {
                    self.refreshChecks()
                    self.finish(restoreMode)
                } else if out.contains("-128") || out.contains("User canceled") {
                    self.status = "已取消（没有输入密码）"
                } else {
                    self.status = "失败"
                    let a = NSAlert()
                    a.messageText = "操作失败"
                    a.informativeText = String(out.suffix(300))
                    a.addButton(withTitle: "查看日志"); a.addButton(withTitle: "关闭")
                    if a.runModal() == .alertFirstButtonReturn { self.openLog() }
                }
            }
        }
        status = "等待管理员授权…"
        try? p.run()
    }

    func openLog() { NSWorkspace.shared.open(logURL) }
    func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color = Color(nsColor: .secondaryLabelColor)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundColor(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.24 : 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CheckRow: View {
    let check: Check
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.info ? "info.circle.fill"
                                          : (check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(check.info
                                 ? Color(nsColor: .secondaryLabelColor)
                                 : (check.ok ? Color(red: 0.2, green: 0.72, blue: 0.42)
                                             : Color(red: 0.95, green: 0.6, blue: 0.15)))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(check.title).font(.system(size: 13, weight: .semibold))
                Text(check.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let act = check.action, !check.actionTitle.isEmpty {
                Button(check.actionTitle, action: act)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct CompactPurpleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let base = isEnabled ? 0.22 : 0.10
        let press = configuration.isPressed && isEnabled
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color.purple.opacity(isEnabled ? 1 : 0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.purple.opacity(press ? base + 0.14 : base))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.purple.opacity(isEnabled ? 0.32 : 0.16), lineWidth: 1)
            )
            .scaleEffect(press ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PrimaryPurpleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    /// 禁用态：偏灰、压暗的紫，仍然能看出是紫色系
    private var fillColor: Color {
        if isEnabled { return Color.purple }
        return Color(red: 0.30, green: 0.24, blue: 0.36).opacity(0.85)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(isEnabled ? 1 : 0.5))
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .frame(minWidth: 108)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled && configuration.isPressed ? Color.purple.opacity(0.82) : fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.purple.opacity(isEnabled ? 0 : 0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 测量 SwiftUI 内容的理想高度
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 首帧把窗口放到屏幕中间；高度交由内容测量后调整
struct WindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window {
                w.title = "汉层 HanLayer"
                w.styleMask.remove(.resizable)
                w.center()
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView: View {
    /// App 图标：优先读取 bundle 内的 icns，回退到系统提供的应用图标
    static var appIcon: NSImage {
        if let path = Bundle.main.path(forResource: "icon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return NSApp.applicationIconImage
    }

    @ObservedObject var runner = Runner()

    var header: some View {
        HStack(spacing: 14) {
            // 直接使用 App 图标，保证与 Dock / 安装包里的图标比例完全一致
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .shadow(color: Color.purple.opacity(0.30), radius: 9, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("汉层 HanLayer")
                    .font(.system(size: 20, weight: .bold))
                Text("Screen Studio 一键汉化 · 官方更新后点一次即可恢复")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !runner.appVersion.isEmpty {
                Text(runner.appVersion)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.purple.opacity(0.14)))
                    .foregroundColor(.purple)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.purple.opacity(0.10), Color.purple.opacity(0.02)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack {
                Text("运行前检查")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.9))
                Spacer()
                Button {
                    runner.refreshChecks()
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CompactPurpleButtonStyle())
                .disabled(runner.running)
            }

            VStack(spacing: 8) {
                ForEach(runner.checks) { c in CheckRow(check: c) }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if runner.running {
                        if let v = runner.progress {
                            ProgressView(value: v).progressViewStyle(.linear).tint(.purple).frame(width: 150)
                        } else {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.55).frame(width: 16)
                        }
                    }
                    Text(runner.status)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                }
                ScrollView {
                    Text(runner.log.isEmpty ? "等待开始…" : runner.log)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .textSelection(.enabled)
                }
                .frame(height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
            }

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                Button { runner.openLog() } label: { Label("查看日志", systemImage: "doc.text") }
                    .buttonStyle(SoftButtonStyle())
                Button { runner.restore() } label: { Label("恢复英文原版", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(SoftButtonStyle(tint: Color(red: 0.95, green: 0.55, blue: 0.2)))
                    .disabled(runner.running || !runner.hasBackup)
                    .opacity(runner.running || !runner.hasBackup ? 0.4 : 1)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(SoftButtonStyle())
                Button {
                    runner.start()
                } label: {
                    Text(runner.running ? "处理中…" : "开始汉化")
                }
                .buttonStyle(PrimaryPurpleButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(runner.running || !runner.ready)
            }
        }
        .padding(18)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowSizer())
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { h in
            guard h > 120, let w = NSApp.windows.first else { return }
            let target = ceil(h)
            let current = w.contentLayoutRect.height
            guard abs(current - target) > 1 || abs(w.frame.width - 680) > 1 else { return }
            var f = w.frame
            let delta = target - current
            f.size.height += delta
            f.origin.y -= delta
            f.size.width = 680 + (w.frame.width - w.contentLayoutRect.width)
            w.setFrame(f, display: true)
        }
        .onAppear { runner.refreshChecks() }
    }
}

@main
struct SSZHLocalizerApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
