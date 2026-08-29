import Foundation

/// Chromium 系ブラウザで JavaScript 実行が許可されている場合、
/// ページ内のフォーム有無・フォーカス要素を調べる。
enum PageProbe {
    struct Info {
        var hasFormTextarea: Bool
        var focusedInput: Bool
    }

    private static let chromiumApps: Set<String> = [
        "Google Chrome", "Arc", "Brave Browser", "Microsoft Edge", "Chromium", "Vivaldi",
    ]

    /// 許可されていない、またはエラーの場合は両方 false を返す(URL ルールだけで判定させる)。
    static func probe(app: String) -> Info {
        guard chromiumApps.contains(app) else {
            return Info(hasFormTextarea: false, focusedInput: false)
        }

        let hasFormScript = """
        tell application "\(app)"
            execute active tab of front window javascript "!!document.querySelector('form textarea')"
        end tell
        """
        let focusedScript = """
        tell application "\(app)"
            execute active tab of front window javascript "document.activeElement.tagName"
        end tell
        """

        let hasFormResult = OSAScript.run(hasFormScript)
        let focusedResult = OSAScript.run(focusedScript)

        let hasForm = hasFormResult?.lowercased() == "true"
        let focused = focusedResult?.uppercased() == "INPUT" || focusedResult?.uppercased() == "TEXTAREA"

        return Info(hasFormTextarea: hasForm, focusedInput: focused)
    }
}
