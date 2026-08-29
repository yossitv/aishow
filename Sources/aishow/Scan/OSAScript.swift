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

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        // osascript が固まって scan 全体を止めないよう、3 秒でタイムアウトして強制終了する。
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard var output = String(data: data, encoding: .utf8) else { return nil }
        if output.hasSuffix("\n") {
            output.removeLast()
        }
        return output
    }
}
