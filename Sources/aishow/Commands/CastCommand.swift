import AishowCore
import Foundation

/// `aishow cast` — stdin のテキストをカーソル位置に貼り付ける(承認後にのみ呼ぶこと)。
///
/// この CLI 自体は承認ゲートを持たない。承認済みテキストしか受け取らない前提であり、
/// 呼び出し元(Step 05 `summon` など)が承認後にのみ呼び出すこと。
///
/// usage: echo "text" | aishow cast [--app "Google Chrome"] [--window-title "..."]
enum CastCommand {
    static func run(_ args: [String]) -> Int32 {
        var appName: String?
        var windowTitle: String?

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--app":
                i += 1
                if i < args.count { appName = args[i] }
            case "--window-title":
                i += 1
                if i < args.count { windowTitle = args[i] }
            default:
                FileHandle.standardError.write("aishow cast: unknown option: \(args[i])\n".data(using: .utf8)!)
                return 64
            }
            i += 1
        }

        // stdin からテキストを読む
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        let text = String(data: stdinData, encoding: .utf8) ?? ""
        let trimmedForCheck = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedForCheck.isEmpty else {
            FileHandle.standardError.write("aishow cast: stdin is empty\n".data(using: .utf8)!)
            return 64
        }

        do {
            let result = try Paster.paste(text: text, appName: appName, windowTitle: windowTitle)
            CastLog.append(app: result.appName, windowTitle: result.windowTitle, chars: result.chars)
            return 0
        } catch let failure as Paster.Failure {
            FileHandle.standardError.write(Paster.message(for: failure).data(using: .utf8)!)
            return Paster.exitCode(for: failure)
        } catch {
            FileHandle.standardError.write("aishow cast: unexpected error: \(error)\n".data(using: .utf8)!)
            return 1
        }
    }
}
