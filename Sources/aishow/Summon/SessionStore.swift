import Foundation

/// `~/.aishow/sessions.json` — `domain(またはapp) → sessionId` の永続マッピング。
/// 同じ会社への再詠唱で同じ TrueForge セッション(履歴)を使い続けるための状態。
enum SessionStore {
    private static func fileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aishow", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    private static func load() -> [String: String] {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }

    private static func save(_ map: [String: String]) {
        let url = fileURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: map, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write("aishow summon: sessions.json 書き込み失敗: \(error)\n".data(using: .utf8)!)
        }
    }

    /// キー: domain があれば domain、無ければ app 名。
    static func key(domain: String?, app: String) -> String {
        domain ?? app
    }

    static func get(key: String) -> String? {
        load()[key]
    }

    static func set(key: String, sessionId: String) {
        var map = load()
        map[key] = sessionId
        save(map)
    }
}
