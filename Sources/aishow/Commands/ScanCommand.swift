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
        // 最前面アプリの取得は自分の UI を出す前に行う(鉄則4)。
        let frontmost = Frontmost.current()

        let browserInfo = BrowserURL.fetch(app: frontmost.app)
        let pageInfo = PageProbe.probe(app: frontmost.app)
        let selectedText = Selection.capture()

        let pack = ContextPack(
            app: frontmost.app,
            windowTitle: frontmost.windowTitle,
            url: browserInfo.url,
            pageTitle: browserInfo.pageTitle,
            selectedText: selectedText,
            focusedInput: pageInfo.focusedInput,
            hasFormTextarea: pageInfo.hasFormTextarea
        )

        let site = detect(pack)
        let result = ScanResult(pack: pack, site: site)

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
