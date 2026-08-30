import AppKit
import ApplicationServices
import Foundation

/// `aishow cast` の中核処理。
///
/// 手順(発注書 step-03-cast.md):
///   1. クリップボード退避(全 pasteboard item / type)
///   2. テキスト書込
///   3. 対象アプリを最前面化(`--app`、省略時は現在の最前面)
///   4. 最前面アプリが対象と一致することを確認(不一致なら中止して 65)
///   5. Cmd+V を CGEvent で送信
///   6. 300ms 後にクリップボード復元(失敗経路でも defer で復元)
///
/// Enter / Return は絶対に送らない。
enum Paster {
    enum Failure: Error {
        case emptyInput
        case appNotFound(String)
        case appNotFrontmost(String)
        case accessibilityNotTrusted
        case pasteEventFailed
    }

    struct Result {
        let appName: String
        let windowTitle: String?
        let chars: Int
    }

    /// 実行結果に応じた終了コードを返す。
    static func exitCode(for error: Failure) -> Int32 {
        switch error {
        case .emptyInput:
            return 64
        case .appNotFound, .appNotFrontmost:
            return 65
        case .accessibilityNotTrusted:
            return 77
        case .pasteEventFailed:
            return 1
        }
    }

    static func message(for error: Failure) -> String {
        switch error {
        case .emptyInput:
            return "aishow cast: stdin is empty\n"
        case .appNotFound(let name):
            return "aishow cast: app not found or not running: \(name)\n"
        case .appNotFrontmost(let name):
            return "aishow cast: aborted — frontmost app is not \(name) after activation. nothing was pasted.\n"
        case .accessibilityNotTrusted:
            return """
            aishow cast: Accessibility permission is required to send Cmd+V.
            System Settings > Privacy & Security > Accessibility で、このターミナル(または aishow を実行しているアプリ)を許可してください。
            \n
            """
        case .pasteEventFailed:
            return "aishow cast: failed to create paste keyboard event\n"
        }
    }

    /// - Parameters:
    ///   - text: 貼り付けるテキスト(承認済み前提)
    ///   - appName: 対象アプリ名(localizedName または bundleIdentifier)。nil なら現在の最前面アプリ
    ///   - windowTitle: ログ用のウィンドウタイトル(任意)
    ///
    /// クリップボードは 300ms 後に復元する(貼り付け先アプリが読み取る時間を確保するため)。
    /// 失敗経路でも必ず復元する。
    static func paste(text: String, appName: String?, windowTitle: String?) throws -> Result {
        guard !text.isEmpty else { throw Failure.emptyInput }
        guard AXIsProcessTrusted() else { throw Failure.accessibilityNotTrusted }

        let pasteboard = NSPasteboard.general
        let savedItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        var thrownError: Error?
        var result: Result?

        do {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            let targetApp = try resolveAndActivate(appName: appName)

            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.processIdentifier == targetApp.processIdentifier else {
                throw Failure.appNotFrontmost(appName ?? targetApp.localizedName ?? "unknown")
            }

            try sendCommandV()

            result = Result(
                appName: targetApp.localizedName ?? appName ?? "unknown",
                windowTitle: windowTitle,
                chars: text.count
            )
        } catch {
            thrownError = error
        }

        // 300ms 後に復元(貼り付け先アプリがクリップボードを読み取る時間を確保)。
        Thread.sleep(forTimeInterval: 0.3)
        restoreClipboard(savedItems, pasteboard: pasteboard)

        if let thrownError {
            throw thrownError
        }
        return result!
    }

    // MARK: - Helpers

    private static func resolveAndActivate(appName: String?) throws -> NSRunningApplication {
        guard let appName else {
            // 省略時は現在の最前面アプリをそのまま対象にする(活性化不要)。
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                throw Failure.appNotFound("(frontmost)")
            }
            return frontmost
        }

        let running = NSWorkspace.shared.runningApplications
        guard let match = running.first(where: {
            $0.localizedName == appName || $0.bundleIdentifier == appName
        }) else {
            throw Failure.appNotFound(appName)
        }

        match.activate(options: [])
        // activate() は非同期的に反映される(macOS 14+ の協調アクティベーションでは遅れることもある)ため、
        // 最前面になるまで最大 1 秒待つ。呼び出し側が最終確認する。
        for _ in 0..<10 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == match.processIdentifier { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return match
    }

    private static func sendCommandV() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw Failure.pasteEventFailed
        }
        let vKeyCode: CGKeyCode = 0x09 // 'v'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw Failure.pasteEventFailed
        }
        // 自分の合成キーだと HotKey が見分けられるように印を付ける
        keyDown.setIntegerValueField(.eventSourceUserData, value: SyntheticKeyEvent.marker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: SyntheticKeyEvent.marker)
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func restoreClipboard(_ items: [NSPasteboardItem], pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
