import AishowCore
import Foundation

/// `scan` の中核処理(索敵)。`ScanCommand`(CLI 出力用)と `SummonCommand` から共有する。
///
/// 鉄則4: 最前面アプリの取得は、呼び出し側が自分の UI(承認ダイアログ等)を出す前に行うこと。
enum Scan {
    struct Result {
        var pack: ContextPack
        var site: SiteDetection
    }

    static func perform() -> Result {
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
        return Result(pack: pack, site: site)
    }
}
