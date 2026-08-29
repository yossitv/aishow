import AppKit
import Foundation

/// 最前面アプリの情報。
struct FrontmostInfo {
    var app: String
    var windowTitle: String?
}

enum Frontmost {
    /// `NSWorkspace.shared.frontmostApplication` を第一情報源、
    /// osascript(System Events)を第二情報源として突き合わせる。
    /// ウィンドウタイトルは System Events の `name of front window` から取得。
    static func current() -> FrontmostInfo {
        var appName: String?

        if let app = NSWorkspace.shared.frontmostApplication {
            appName = app.localizedName
        }

        let windowTitle = frontWindowTitle()

        if appName == nil {
            appName = osascriptFrontmostAppName()
        }

        return FrontmostInfo(app: appName ?? "unknown", windowTitle: windowTitle)
    }

    private static func osascriptFrontmostAppName() -> String? {
        let script = """
        tell application "System Events"
            name of first application process whose frontmost is true
        end tell
        """
        return OSAScript.run(script)
    }

    private static func frontWindowTitle() -> String? {
        let script = """
        tell application "System Events"
            tell (first application process whose frontmost is true)
                try
                    name of front window
                on error
                    ""
                end try
            end tell
        end tell
        """
        let result = OSAScript.run(script)
        guard let result, !result.isEmpty else { return nil }
        return result
    }
}
