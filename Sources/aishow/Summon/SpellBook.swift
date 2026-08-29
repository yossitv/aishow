import Foundation

/// `harness/spells/_common.md` + 全 `harness/spells/*.md` を連結してエージェントの `instructions` を組み立てる。
/// TrueForge の Skills 機能(sandbox 必須)は使わず、呪文をそのまま instructions に埋め込む
/// (`step-05-summon.md` の設計変更)。
enum SpellBook {
    /// `harness/spells` の探索順(cwd 非依存。`make app` → `open dist/Aishow.app` だと cwd が `/` になるため):
    /// (a) $AISHOW_HOME/harness/spells (b) cwd/harness/spells (c) Bundle.main.resourceURL/harness/spells
    /// (d) 実行ファイルから4階層上/harness/spells (e) ~/Documents/GitHub/aishow/harness/spells
    private static var spellsDir: URL {
        let fm = FileManager.default

        if let home = ProcessInfo.processInfo.environment["AISHOW_HOME"], !home.isEmpty {
            let candidate = URL(fileURLWithPath: home).appendingPathComponent("harness/spells")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }

        let cwdCandidate = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("harness/spells")
        if fm.fileExists(atPath: cwdCandidate.path) { return cwdCandidate }

        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("harness/spells")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }

        // 実行ファイル: dist/Aishow.app/Contents/MacOS/Aishow → 4階層上がリポジトリルート想定
        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let fromExe = exeURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("harness/spells")
        if fm.fileExists(atPath: fromExe.path) { return fromExe }

        let fallback = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/GitHub/aishow/harness/spells")
        return fallback
    }

    static let outputContract = """

    ---
    最終回答は必ず次の JSON 1 個を ```json フェンスで返すこと:
    {"sources": ["根拠にしたURL", ...], "text": "貼り付ける本文(英語)", "note": "調査不足なら理由。無ければ省略可"}
    text が空文字列、または調査不足で確信が持てない場合は貼り付けない。貼り付け・送信はアプリ側が人間の承認後に行うので、ツールで貼り付けようとしないこと。
    """

    /// instructions 文字列を組み立てる。`_common.md` が無い場合は空文字列から始める。
    static func buildInstructions() -> String {
        var parts: [String] = []
        let dir = spellsDir

        let commonPath = dir.appendingPathComponent("_common.md")
        if let common = try? String(contentsOf: commonPath, encoding: .utf8) {
            parts.append(common)
        } else {
            FileHandle.standardError.write(
                "aishow: harness/spells が見つかりません(探索先: \(dir.path))。AISHOW_HOME を設定するか、リポジトリ直下で実行してください\n".data(using: .utf8)!
            )
        }

        if let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let spellFiles = entries
                .filter { $0.pathExtension == "md" && $0.lastPathComponent != "_common.md" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in spellFiles {
                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    parts.append(content)
                }
            }
        }

        parts.append(outputContract)
        return parts.joined(separator: "\n\n")
    }
}
