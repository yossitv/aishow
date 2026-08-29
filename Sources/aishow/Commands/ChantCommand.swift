import AishowCore
import Foundation

/// `aishow chant` — 録音(または `--file`)→ OpenAI STT → 認識テキストを stdout に出す。
enum ChantCommand {
    static func run(_ args: [String]) -> Int32 {
        let filePath = parseFileOption(args)

        switch Chant.capture(filePath: filePath) {
        case .success(let text):
            print(text)
            return 0
        case .failure(let failure):
            writeErr(failure.message)
            return failure.exitCode
        }
    }

    private static func parseFileOption(_ args: [String]) -> String? {
        var index = 0
        while index < args.count {
            if args[index] == "--file", index + 1 < args.count {
                return args[index + 1]
            }
            index += 1
        }
        return nil
    }

    private static func writeErr(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
