import Foundation

/// 環境変数を読む。未設定ならカレントディレクトリの `.env` を読んで補完する。
/// 値は絶対にログへ出さないこと。
enum Env {
    static func get(_ key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        return dotEnv[key]
    }

    /// カレントディレクトリの `.env` を一度だけ読む(簡易パーサ: `KEY=VALUE`、`#` コメント、引用符除去)。
    static let dotEnv: [String: String] = loadDotEnv()

    private static func loadDotEnv() -> [String: String] {
        let path = FileManager.default.currentDirectoryPath + "/.env"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        var result: [String: String] = [:]
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let eqIndex = line.firstIndex(of: "=") else { continue }

            let key = String(line[line.startIndex..<eqIndex]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            var value = String(line[line.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}
