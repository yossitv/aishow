import AishowCore
import Foundation

/// `aishow scan [--json]` — 最前面アプリ・URL・選択テキストを索敵し、
/// `{ "pack": ContextPack, "site": SiteDetection }` を stdout に JSON で出力する。
enum ScanCommand {
    private struct ScanResult: Codable {
        var pack: ContextPack
        var site: SiteDetection
    }

    static func run(_ args: [String]) -> Int32 {
        let scanned = Scan.perform()
        let result = ScanResult(pack: scanned.pack, site: scanned.site)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(result)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write("\n".data(using: .utf8)!)
            return 0
        } catch {
            FileHandle.standardError.write("aishow scan: encode error: \(error)\n".data(using: .utf8)!)
            return 1
        }
    }
}
