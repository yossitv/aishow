import Foundation

/// `~/.aishow/log.jsonl` への追記ログ。本文(text)は保存しない。
enum CastLog {
    struct Entry: Encodable {
        let ts: String
        let app: String
        let windowTitle: String?
        let chars: Int
        let source: String
    }

    static func logDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aishow", isDirectory: true)
    }

    static func logFile() -> URL {
        logDirectory().appendingPathComponent("log.jsonl")
    }

    /// 1 行の JSON を追記する。ディレクトリが無ければ作成する。
    static func append(app: String, windowTitle: String?, chars: Int, source: String = "cast") {
        let dir = logDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let entry = Entry(
                ts: formatter.string(from: Date()),
                app: app,
                windowTitle: windowTitle,
                chars: chars,
                source: source
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(entry)
            guard let line = String(data: data, encoding: .utf8) else { return }

            let fileURL = logFile()
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let lineData = (line + "\n").data(using: .utf8) {
                handle.write(lineData)
            }
        } catch {
            // ログ書き込み失敗は cast 自体の成否に影響させない。標準エラーにだけ出す。
            FileHandle.standardError.write("aishow cast: log write failed: \(error)\n".data(using: .utf8)!)
        }
    }
}
