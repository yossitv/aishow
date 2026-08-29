import Foundation

/// 環境変数を読む。未設定なら `.env` を探して補完する。cwd に依存しない探索順にする
/// (`make app` → `open dist/Aishow.app` だと cwd が `/` になるため)。
/// 値は絶対にログへ出さないこと。
enum Env {
    static func get(_ key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        return dotEnv[key]
    }

    /// `.env` を一度だけ読む(簡易パーサ: `KEY=VALUE`、`#` コメント、引用符除去)。
    /// 探索順: (a) $AISHOW_HOME/.env (b) cwd/.env (c) ~/.aishow/.env
    /// (d) 実行ファイルから4階層上/.env (e) ~/Documents/GitHub/aishow/.env
    static let dotEnv: [String: String] = loadDotEnv()

    private static func loadDotEnv() -> [String: String] {
        let fm = FileManager.default
        var candidates: [String] = []

        if let home = ProcessInfo.processInfo.environment["AISHOW_HOME"], !home.isEmpty {
            candidates.append(home + "/.env")
        }
        candidates.append(fm.currentDirectoryPath + "/.env")
        candidates.append(NSHomeDirectory() + "/.aishow/.env")
        // 実行ファイル: dist/Aishow.app/Contents/MacOS/Aishow → 4階層上がリポジトリルート想定
        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let fromExe = exeURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".env")
            .path
        candidates.append(fromExe)
        candidates.append(NSHomeDirectory() + "/Documents/GitHub/aishow/.env")

        for path in candidates {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return parse(content)
            }
        }
        return [:]
    }

    private static func parse(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
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
