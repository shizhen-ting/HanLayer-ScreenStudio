import SwiftUI
import AppKit

struct Check: Identifiable {
    let id = UUID()
    var ok: Bool
    var title: String
    var detail: String
    var action: (() -> Void)? = nil
    var actionTitle: String = ""
}

final class Runner: ObservableObject {
    @Published var running = false
    @Published var status = "准备就绪：点「开始汉化」即可"
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

    func refreshChecks() {
        var list: [Check] = []
        if let app = ssPath {
            let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")
            appVersion = info?["CFBundleShortVersionString"] as? String ?? "未知版本"
            list.append(Check(ok: true, title: "已找到 Screen Studio", detail: appVersion,
                              action: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app)]) },
                              actionTitle: "在访达中显示"))
            let writable = probeWritable(app)
            list.append(Check(ok: writable,
                              title: writable ? "App 管理权限已开启" : "App 管理权限未开启",
                              detail: writable ? "可以直接改写 Screen Studio，不会弹密码"
                                               : "点「打开设置」去勾选本程序，以后就不弹密码；不勾也可以，会要求输入 Mac 密码",
                              action: { self.openAppManagement() },
                              actionTitle: "打开设置"))
        } else {
            list.append(Check(ok: false, title: "没找到 Screen Studio",
                              detail: "默认找「应用程序」文件夹；装在别处就手动选，没装过就去官网下载",
                              action: { self.pickApp() },
                              actionTitle: "选择位置…"))
            list.append(Check(ok: false, title: "还没装 Screen Studio？",
                              detail: "可以去官网下载安装包，装好再回来点「重新检查」",
                              action: { NSWorkspace.shared.open(URL(string: "https://screen.studio")!) },
                              actionTitle: "打开官网"))
        }
        list.append(Check(ok: true,
                          title: "汉化后 Screen Studio 需重新授权",
                          detail: "屏幕录制 / 辅助功能 / 摄像头 —— 签名变了，系统会重新弹窗",
                          action: { self.openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") },
                          actionTitle: "打开屏幕录制设置"))
        list.append(Check(ok: true, title: "运行环境已内置",
                          detail: "不需要另外装 Python，汉化引擎打包在工具里"))
        checks = list
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

    func probeWritable(_ app: String) -> Bool {
        let probe = app + "/Contents/Resources/.sszh-probe"
        do {
            try "x".write(toFile: probe, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probe)
            return true
        } catch { return false }
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

        if checks.contains(where: { $0.title.contains("App 管理权限未开启") }) {
            let a = NSAlert()
            a.messageText = "App 管理权限未开启"
            a.informativeText = "继续会弹出要求输入 Mac 登录密码的窗口，输入后同样能完成汉化。\n想让以后一键无密码：去「系统设置 → 隐私与安全性 → App 管理」勾选「汉层 HanLayer」。"
            a.addButton(withTitle: "继续（输密码）")
            a.addButton(withTitle: "我先去开权限")
            if a.runModal() != .alertFirstButtonReturn {
                openAppManagement(); return
            }
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
            Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(check.ok ? Color(red: 0.2, green: 0.72, blue: 0.42) : Color(red: 0.95, green: 0.6, blue: 0.15))
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

struct WindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window {
                w.setContentSize(NSSize(width: 680, height: 690))
                w.center()
                w.title = "汉层 HanLayer"
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView: View {
    @ObservedObject var runner = Runner()

    var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.40, blue: 1.0),
                                                  Color(red: 0.33, green: 0.16, blue: 0.78)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("汉层")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 62, height: 62)
            .shadow(color: Color.purple.opacity(0.35), radius: 10, x: 0, y: 4)

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
                Text("运行前检查").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                Button {
                    runner.refreshChecks()
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
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
                    .disabled(runner.running)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(SoftButtonStyle())
                Button {
                    runner.start()
                } label: {
                    Text(runner.running ? "处理中…" : "开始汉化")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 92)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(runner.running)
            }
        }
        .padding(18)
        .frame(width: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowSizer())
        .onAppear { runner.refreshChecks() }
    }
}

@main
struct SSZHLocalizerApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
