import Foundation

/// 简单文件日志：写入 ~/Library/Logs/WTidy.log，超过 512KB 自动轮转。
/// 所有写操作走串行队列，线程安全。
final class AppLog {
    static let shared = AppLog()

    private let queue = DispatchQueue(label: "com.allblue.wtidy.log")
    private let maxBytes = 512 * 1024
    private var handle: FileHandle?
    private let url: URL

    private init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WTidy.log")
        openHandle()
    }

    static func info(_ message: String) { shared.write("INFO ", message) }
    static func warn(_ message: String) { shared.write("WARN ", message) }
    static func error(_ message: String) { shared.write("ERROR", message) }

    var logPath: URL { url }

    // MARK: - Private

    private func openHandle() {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: url.path)
        _ = try? handle?.seekToEnd()
    }

    private func write(_ level: String, _ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) [\(level)] \(message)\n"
        queue.async { [weak self] in
            guard let self = self else { return }
            self.rotateIfNeeded()
            guard let data = line.data(using: .utf8) else { return }
            self.handle?.write(data)
        }
    }

    private func rotateIfNeeded() {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size > maxBytes else { return }
        handle?.closeFile()
        try? FileManager.default.moveItem(at: url, to: URL(fileURLWithPath: url.path + ".old"))
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = FileHandle(forWritingAtPath: url.path)
    }
}
