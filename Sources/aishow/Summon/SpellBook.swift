import Foundation

/// `harness/spells/_common.md` + 全 `harness/spells/*.md` を連結してエージェントの `instructions` を組み立てる。
/// TrueForge の Skills 機能(sandbox 必須)は使わず、呪文をそのまま instructions に埋め込む
/// (`step-05-summon.md` の設計変更)。
enum SpellBook {
    /// `harness/spells` は現在の作業ディレクトリからの相対パスで探す(`Env` の `.env` 探索と同じ流儀)。
    private static var spellsDir: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("harness/spells")
    }

    static let outputContract = """

    ---
    最終回答は必ず次の JSON 1 個を ```json フェンスで返すこと:
    {"sources": ["根拠にしたURL", ...], "text": "貼り付ける本文(英語)", "note": "調査不足なら理由。無ければ省略可"}
    text が空文字列、または調査不足で確信が持てない場合は貼り付けない(paste_to_cursor を呼ばない)。
    """

    /// instructions 文字列を組み立てる。`_common.md` が無い場合は空文字列から始める。
    static func buildInstructions() -> String {
        var parts: [String] = []

        let commonPath = spellsDir.appendingPathComponent("_common.md")
        if let common = try? String(contentsOf: commonPath, encoding: .utf8) {
            parts.append(common)
        }

        if let entries = try? FileManager.default.contentsOfDirectory(at: spellsDir, includingPropertiesForKeys: nil) {
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
