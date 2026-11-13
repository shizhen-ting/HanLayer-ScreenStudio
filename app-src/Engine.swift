import Foundation

enum EngineError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

struct AsarEntry {
    var path: String
    var size: Int
    var offset: Int?
    var unpacked: Bool
    var link: String?
}

final class Engine {
    static let identity = "Screen Studio Chinese Localizer"
    static let unpackedDirs = ["bin", "node_modules/keytar", "node_modules/node-mac-permissions", "node_modules/wallpaper"]

    let assetsDir: String
    var onProgress: ((String, Double) -> Void)?

    init() {
        assetsDir = (Bundle.main.resourcePath ?? "") + "/engine/assets"
    }

    // MARK: - helpers

    func log(_ s: String, _ p: Double) { onProgress?(s, p) }

    func read(_ p: String) throws -> String {
        guard let s = try? String(contentsOfFile: p, encoding: .utf8) else {
            throw EngineError.message("读取失败：\(p)")
        }
        return s
    }

    func write(_ s: String, _ p: String) throws {
        do { try s.write(toFile: p, atomically: true, encoding: .utf8) }
        catch { throw EngineError.message("写入失败：\(p)") }
    }

    @discardableResult
    func run(_ launch: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ELECTRON_RUN_AS_NODE")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    func consoleUser() -> String? {
        let (st, out) = run("/usr/bin/stat", ["-f", "%Su", "/dev/console"])
        guard st == 0 else { return nil }
        let u = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty ? nil : u
    }

    func homeDir() -> String {
        if geteuid() == 0, let u = consoleUser(), FileManager.default.fileExists(atPath: "/Users/\(u)") {
            return "/Users/\(u)"
        }
        return NSHomeDirectory()
    }

    // MARK: - asar

    func extractAsar(_ asar: String, to dest: String) throws {
        guard let fh = FileHandle(forReadingAtPath: asar) else {
            throw EngineError.message("打不开 app.asar")
        }
        defer { try? fh.close() }
        try? fh.seek(toOffset: 4)
        let hdrLenData = fh.readData(ofLength: 4)
        guard hdrLenData.count == 4 else { throw EngineError.message("asar 头读取失败") }
        let hdrLen = Int(hdrLenData.withUnsafeBytes { $0.load(as: UInt32.self) })
        try? fh.seek(toOffset: 8)
        let headerBuf = fh.readData(ofLength: hdrLen)
        guard headerBuf.count >= 8 else { throw EngineError.message("asar 头损坏") }
        let jsonLen = Int(headerBuf.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) })
        guard headerBuf.count >= 8 + jsonLen else { throw EngineError.message("asar 头长度不对") }
        let jsonData = headerBuf.subdata(in: 8..<(8 + jsonLen))
        let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        let dataStart = 8 + hdrLen + 12  // 8 + (4 + payloadLen) ; payload starts at 12
        let realStart = 8 + hdrLen
        _ = dataStart

        let unpackedRoot = asar + ".unpacked"
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)

        func walk(_ node: [String: Any], _ prefix: String) throws {
            guard let files = node["files"] as? [String: Any] else { return }
            for (name, value) in files {
                guard let meta = value as? [String: Any] else { continue }
                let rel = prefix.isEmpty ? name : prefix + "/" + name
                let full = dest + "/" + rel
                if meta["files"] != nil {
                    try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
                    try walk(meta, rel)
                } else if let link = meta["link"] as? String {
                    try? FileManager.default.removeItem(atPath: full)
                    try? FileManager.default.createSymbolicLink(atPath: full, withDestinationPath: link)
                } else {
                    try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                    if (meta["unpacked"] as? Bool) == true {
                        let src = unpackedRoot + "/" + rel
                        if FileManager.default.fileExists(atPath: src) {
                            try? FileManager.default.removeItem(atPath: full)
                            try FileManager.default.copyItem(atPath: src, toPath: full)
                        } else {
                            FileManager.default.createFile(atPath: full, contents: Data())
                        }
                    } else {
                        let offset = Int((meta["offset"] as? String) ?? "0") ?? 0
                        let size = (meta["size"] as? Int) ?? 0
                        try? fh.seek(toOffset: UInt64(realStart + offset))
                        let d = fh.readData(ofLength: size)
                        try d.write(to: URL(fileURLWithPath: full))
                    }
                }
            }
        }
        try walk(root ?? [:], "")
    }

    func packAsar(_ src: String, to out: String) throws {
        func isUnpacked(_ rel: String) -> Bool {
            for d in Self.unpackedDirs where rel == d || rel.hasPrefix(d + "/") { return true }
            return false
        }
        var order: [(String, [String: Any])] = []

        func walk(_ dir: String, _ prefix: String) throws -> [String: Any] {
            var files: [String: Any] = [:]
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.sorted() ?? []
            for name in names {
                if prefix.isEmpty && name == "app.asar.unpacked" { continue }
                let rel = prefix.isEmpty ? name : prefix + "/" + name
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: dir + "/" + name, isDirectory: &isDir)
                if isDir.boolValue {
                    files[name] = ["files": try walk(dir + "/" + name, rel)]
                } else {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: dir + "/" + name)
                    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    var meta: [String: Any] = ["size": size]
                    if isUnpacked(rel) { meta["unpacked"] = true } else { meta["offset"] = "0" }
                    files[name] = meta
                    order.append((rel, meta))
                }
            }
            return files
        }

        let tree = try walk(src, "")
        // assign offsets in same order as JSON traversal
        var offset = 0
        func assign(_ node: [String: Any], _ prefix: String) {
            guard let files = node["files"] as? [String: Any] else { return }
            for name in files.keys.sorted() {
                guard var meta = files[name] as? [String: Any] else { continue }
                let rel = prefix.isEmpty ? name : prefix + "/" + name
                if meta["files"] != nil {
                    assign(meta, rel)
                } else if (meta["unpacked"] as? Bool) == true {
                    // no offset
                } else {
                    meta["offset"] = String(offset)
                    offset += (meta["size"] as? Int) ?? 0
                    var parent = node["files"] as! [String: Any]
                    parent[name] = meta
                    // mutate parent in place is not possible for let node; rebuild below
                    _ = parent
                }
            }
        }
        _ = assign

        // rebuild tree with offsets properly (ordered, deterministic)
        var computed: [(String, Int)] = []
        func recompute(_ dir: String, _ prefix: String) throws -> [String: Any] {
            var files: [String: Any] = [:]
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.sorted() ?? []
            for name in names {
                if prefix.isEmpty && name == "app.asar.unpacked" { continue }
                let rel = prefix.isEmpty ? name : prefix + "/" + name
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: dir + "/" + name, isDirectory: &isDir)
                if isDir.boolValue {
                    files[name] = ["files": try recompute(dir + "/" + name, rel)]
                } else {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: dir + "/" + name)
                    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    var meta: [String: Any] = ["size": size]
                    if isUnpacked(rel) {
                        meta["unpacked"] = true
                    } else {
                        meta["offset"] = String(computed.count >= 0 ? currentOffset : 0)
                        currentOffset += size
                    }
                    files[name] = meta
                    computed.append((rel, 0))
                }
            }
            return files
        }
        // simple deterministic pass with a running offset
        var currentOffset = 0
        computed = []
        let finalTree = try recompute(src, "")

        let json = try JSONSerialization.data(withJSONObject: ["files": finalTree], options: [.sortedKeys])
        let jsonLen = json.count
        var payloadLen = 4 + jsonLen
        payloadLen = (payloadLen + 63) / 64 * 64
        var payload = Data()
        var jl = UInt32(jsonLen).littleEndian
        withUnsafeBytes(of: &jl) { payload.append(contentsOf: $0) }
        payload.append(json)
        payload.append(Data(repeating: 0, count: payloadLen - payload.count))
        var headerBuf = Data()
        var pl = UInt32(payloadLen).littleEndian
        withUnsafeBytes(of: &pl) { headerBuf.append(contentsOf: $0) }
        headerBuf.append(payload)

        var fileData = Data()
        var a = UInt32(4).littleEndian
        withUnsafeBytes(of: &a) { fileData.append(contentsOf: $0) }
        var b = UInt32(headerBuf.count).littleEndian
        withUnsafeBytes(of: &b) { fileData.append(contentsOf: $0) }
        fileData.append(headerBuf)

        // append file contents in the same order the tree was built
        func appendFiles(_ dir: String, _ prefix: String) throws {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.sorted() ?? []
            for name in names {
                if prefix.isEmpty && name == "app.asar.unpacked" { continue }
                let rel = prefix.isEmpty ? name : prefix + "/" + name
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: dir + "/" + name, isDirectory: &isDir)
                if isDir.boolValue {
                    try appendFiles(dir + "/" + name, rel)
                } else if !isUnpacked(rel) {
                    if let d = FileManager.default.contents(atPath: dir + "/" + name) { fileData.append(d) }
                }
            }
        }
        try appendFiles(src, "")
        try fileData.write(to: URL(fileURLWithPath: out))

        // unpacked copies
        let upRoot = out + ".unpacked"
        try? FileManager.default.removeItem(atPath: upRoot)
        for d in Self.unpackedDirs {
            let srcDir = src + "/" + d
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: srcDir, isDirectory: &isDir), isDir.boolValue else { continue }
            try? FileManager.default.copyItem(atPath: srcDir, toPath: upRoot + "/" + d)
        }
    }
}
