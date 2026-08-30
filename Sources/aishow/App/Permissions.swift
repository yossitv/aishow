import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// 初回起動時の権限チェック(マイク / Accessibility / Automation)。
enum Permissions {
    struct Status {
        var accessibility: Bool
        var microphone: Bool
        var automation: Bool
    }

    /// 現在の許可状況を調べる。Automation は実際に `osascript` で System Events を
    /// 1 回叩いて判定する(叩かないと許可ダイアログ自体が出ないため)。
    static func check() -> Status {
        Status(
            accessibility: AXIsProcessTrusted(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            automation: checkAutomation()
        )
    }

    /// Accessibility が未許可なら macOS 標準の許可ダイアログ(「システム設定を開く」ボタン付き)を出す。
    /// VoiceInk などと同じ方式で、ユーザーが自分で一覧に追加する手間をなくす。ダイアログは 1 プロセスにつき 1 回だけ出る。
    @discardableResult
    static func promptAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// マイクの許可ダイアログを出す(未決定の場合のみ)。
    static func requestMicrophoneIfNeeded(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        default:
            completion(false)
        }
    }

    /// System Settings の該当ペインを開く。
    static func openSystemSettings(pane: SettingsPane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    enum SettingsPane {
        case accessibility
        case microphone
        case automation

        var urlString: String {
            switch self {
            case .accessibility:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .microphone:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            case .automation:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            }
        }
    }

    /// System Events に `name of first process` を尋ねて Automation 許可を判定する。
    /// 未許可なら初回はここで許可ダイアログが出る。
    private static func checkAutomation() -> Bool {
        let script = """
        tell application "System Events" to get name of first application process
        """
        return OSAScript.run(script) != nil
    }
}
