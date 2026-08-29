import AishowCore
import Foundation

/// `chant` の中核処理(録音 → STT)。`ChantCommand` と `SummonCommand` から共有する。
enum Chant {
    /// 失敗時の (終了コード, メッセージ)。
    struct Failure: Error {
        let exitCode: Int32
        let message: String
    }

    /// - Parameter filePath: 指定があれば録音の代わりにこのファイルを使う(テスト用)。
    static func capture(filePath: String? = nil) -> Swift.Result<String, Failure> {
        let audioURL: URL
        let cleanupURL: URL?

        if let filePath {
            let candidate = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                return .failure(Failure(exitCode: 1, message: "指定された音声ファイルが見つかりません: \(filePath)"))
            }
            audioURL = candidate
            cleanupURL = nil
        } else {
            switch Recorder.record() {
            case .success(let url):
                audioURL = url
                cleanupURL = url
            case .failure(.permissionDenied):
                return .failure(Failure(
                    exitCode: 77,
                    message: "マイクへのアクセスが許可されていません。システム設定 > プライバシーとセキュリティ > マイク で aishow を許可してください。"
                ))
            case .failure(.engineError(let message)):
                return .failure(Failure(exitCode: 1, message: "録音エラー: \(message)"))
            }
        }

        defer {
            if let cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }

        if let duration = WavUtil.duration(ofWavAt: audioURL), duration < 1.0 {
            return .failure(Failure(exitCode: 66, message: "詠唱が短すぎる"))
        }

        switch Transcriber.transcribe(fileURL: audioURL) {
        case .success(let text):
            return .success(text)
        case .failure(.missingApiKey):
            return .failure(Failure(exitCode: 78, message: "OPENAI_API_KEY が設定されていません。環境変数か .env に設定してください。"))
        case .failure(.requestFailed(let message)):
            return .failure(Failure(exitCode: 1, message: "文字起こしに失敗しました: \(message)"))
        }
    }
}
