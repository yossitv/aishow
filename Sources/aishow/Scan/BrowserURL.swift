import Foundation

/// ブラウザのアクティブタブから URL / タイトルを取得する。
enum BrowserURL {
    struct Info {
        var url: String?
        var pageTitle: String?
    }

    /// アプリ名からブラウザかどうかを判定し、取得できれば `Info` を返す。
    /// 取得できない(対象アプリでない・スクリプトが失敗する)場合は nil を含む Info を返す。
    static func fetch(app: String) -> Info {
        switch app {
        case "Google Chrome", "Arc", "Brave Browser", "Microsoft Edge", "Chromium", "Vivaldi":
            return fetchChromiumFamily(appName: app)
        case "Safari":
            return fetchSafari()
        default:
            return Info(url: nil, pageTitle: nil)
        }
    }

    private static func fetchChromiumFamily(appName: String) -> Info {
        let urlScript = """
        tell application "\(appName)" to get URL of active tab of front window
        """
        let titleScript = """
        tell application "\(appName)" to get title of active tab of front window
        """
        let url = OSAScript.run(urlScript)
        let title = OSAScript.run(titleScript)
        return Info(url: url, pageTitle: title)
    }

    private static func fetchSafari() -> Info {
        let urlScript = """
        tell application "Safari" to get URL of front document
        """
        let titleScript = """
        tell application "Safari" to get name of front document
        """
        let url = OSAScript.run(urlScript)
        let title = OSAScript.run(titleScript)
        return Info(url: url, pageTitle: title)
    }
}
