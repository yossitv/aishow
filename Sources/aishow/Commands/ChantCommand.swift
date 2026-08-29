import AishowCore
import Foundation

/// `aishow chant` — 録音(または `--file`)→ OpenAI STT → 認識テキストを stdout に出す。
enum ChantCommand {
    static func run(_ args: [String]) -> Int32 {
        let filePath = parseFileOption(args)

        let audioURL: URL
        let cleanupURL: URL?

        if let filePath {
            let candidate = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                writeErr("指定された音声ファイルが見つかりません: \(filePath)")
                return 1
            }
            audioURL = candidate
            cleanupURL = nil
        } else {
            switch Recorder.record() {
            case .success(let url):
                audioURL = url
                cleanupURL = url
            case .failure(.permissionDenied):
                writeErr("マイクへのアクセスが許可されていません。システム設定 > プライバシーとセキュリティ > マイク で aishow を許可してください。")
                return 77
            case .failure(.engineError(let message)):
                writeErr("録音エラー: \(message)")
                return 1
            }
        }

        defer {
            if let cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }

        if let duration = WavUtil.duration(ofWavAt: audioURL), duration < 1.0 {
            writeErr("詠唱が短すぎる")
            return 66
        }

        switch Transcriber.transcribe(fileURL: audioURL) {
        case .success(let text):
            print(text)
            return 0
        case .failure(.missingApiKey):
            writeErr("OPENAI_API_KEY が設定されていません。環境変数か .env に設定してください。")
            return 78
        case .failure(.requestFailed(let message)):
            writeErr("文字起こしに失敗しました: \(message)")
            return 1
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
