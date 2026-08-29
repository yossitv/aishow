import Foundation

/// `/usr/bin/osascript` を `Process` で呼び出す共通ヘルパー。
enum OSAScript {
    /// AppleScript を実行し、標準出力(末尾改行を除く)を返す。失敗時は nil。
    @discardableResult
    static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard var output = String(data: data, encoding: .utf8) else { return nil }
        if output.hasSuffix("\n") {
            output.removeLast()
        }
        return output
    }
}
