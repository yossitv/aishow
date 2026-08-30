import Combine
import Foundation

/// UI 表示言語。既定は English。
enum UILanguage: String, CaseIterable {
    case en
    case ja

    /// Settings の Picker に出す表示名。
    var displayName: String {
        switch self {
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
}

/// メニューバー UI の表示言語を保持する。切り替えは即時反映(再起動不要)。
/// SwiftUI ビューは `@ObservedObject`(または `@StateObject`)で `L10n.shared` を購読することで
/// 言語変更時に再描画される。
@MainActor
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: UILanguage {
        didSet {
            Preferences.uiLanguage = language
        }
    }

    private init() {
        language = Preferences.uiLanguage
    }

    /// 引数無しの単純なローカライズ文字列。テーブルに無いキーはそのまま返す(クラッシュしない)。
    /// `nonisolated`: `HotKey` / `Pipeline`(stub)等、MainActor に隔離されていない箇所からも呼べるようにする。
    /// 現在の言語は `Preferences.uiLanguage`(`L10n.shared.language` の didSet で即時同期される)から読む。
    nonisolated static func t(_ key: String) -> String {
        let language = Preferences.uiLanguage
        return table[language]?[key] ?? table[.en]?[key] ?? key
    }

    /// `String(format:)` を通す引数付き版。
    nonisolated static func t(_ key: String, _ args: CVarArg...) -> String {
        let language = Preferences.uiLanguage
        let format = table[language]?[key] ?? table[.en]?[key] ?? key
        return String(format: format, arguments: args)
    }

    /// 英語・日本語の文言テーブル。キーは `"scope.name"` の dot 形式。
    nonisolated private static let table: [UILanguage: [String: String]] = [
        .en: [
            // 状態(AppState)
            "status.ready": "Ready — hold %@ to chant",
            "status.scanned": "Scanned ✔",
            "status.chanting": "Chanting…",
            "status.transcribing": "Transcribing…",
            "status.summoning": "Summoning / %@",
            "status.summoningPending": "Summoning…",
            "status.awaitingApproval": "Awaiting approval",
            "status.pastedInto": "Pasted into %@ ✔ — review and press Enter yourself",
            "status.cancelled": "Cancelled",
            "status.error": "Error",

            // StatusView
            "status.now": "Now",
            "status.pending": "Pending",
            "status.done": "Done",
            "status.dash": "-",
            "status.permissionsNeeded": "Permissions needed",
            "status.allowAccessibility": "Allow Accessibility…",
            "status.allowMicrophone": "Allow Microphone…",
            "status.allowAutomation": "Allow Automation…",
            "status.fnModeNote": "Fn (🌐) mode: Set System Settings → Keyboard → “Press 🌐 key to” = Do Nothing",

            // ApprovalView
            "approval.title": "Approve summon result",
            "approval.sources": "Sources",
            "approval.textEditable": "Text (editable)",
            "approval.pasteInto": "Paste into",
            "approval.frontChanged": "⚠️ Front app changed since scan: %@. Please check the paste target.",
            "approval.reject": "Reject",
            "approval.pasteAnyway": "Paste anyway",
            "approval.approve": "Approve",
            "approval.hint": "⏎ Approve · ⇧⏎ New line · Esc Reject",

            // HUDPanel
            "hud.cancel": "Cancel",

            // SettingsView
            "settings.title": "Settings",
            "settings.hotkey": "Hotkey",
            "settings.translateInto": "Translate into",
            "settings.language": "Language",
            "settings.fnNote": "Set System Settings → Keyboard → “Press 🌐 key to” = Do Nothing",
            "settings.optionConflict": "Conflicts with the ChatGPT app’s default shortcut",
            "settings.translateAuto": "Auto (JA ⇄ EN)",
            "settings.translateNote": "Used by the translate workflow (anywhere that isn’t a form, LinkedIn, chat, or mail)",

            // MenuBarApp
            "menu.status": "Status…",
            "menu.settings": "Settings…",
            "menu.quit": "Quit",
            "approvalWindow.title": "Approve",

            // エラー
            "error.pasteFailed": "Paste failed: %@",
            "error.transcriptionFailed": "Transcription failed: %@",
            "error.summonFailed": "Summon failed: %@",
            "error.regenerationFailed": "Regeneration failed: %@",
            "error.chantTooShort": "Chant too short or recording failed",
            "error.accessibilityRequired": "Accessibility permission is required to listen for the hotkey",

            // ホットキー表示名
            "hotkey.holdCmdEither": "Hold ⌘ (either)",
            "hotkey.holdRightCmd": "Hold Right ⌘",
            "hotkey.holdLeftCmd": "Hold Left ⌘",
            "hotkey.holdFn": "Hold Fn (🌐)",

            // Pipeline(stub)
            "pipeline.summoningStub": "Summoning…",
        ],
        .ja: [
            "status.ready": "待機中 — %@ で詠唱",
            "status.scanned": "索敵完了 ✔",
            "status.chanting": "詠唱中…",
            "status.transcribing": "文字起こし中…",
            "status.summoning": "召喚中 / %@",
            "status.summoningPending": "召喚中…",
            "status.awaitingApproval": "承認待ち",
            "status.pastedInto": "%@ に貼り付けました ✔ — 内容を確認して Enter はご自身で",
            "status.cancelled": "キャンセルしました",
            "status.error": "エラー",

            "status.now": "いま",
            "status.pending": "待ち",
            "status.done": "済み",
            "status.dash": "-",
            "status.permissionsNeeded": "権限が不足しています",
            "status.allowAccessibility": "Accessibility を許可…",
            "status.allowMicrophone": "Microphone を許可…",
            "status.allowAutomation": "Automation を許可…",
            "status.fnModeNote": "Fn(🌐)モード: システム設定 → キーボード → 「🌐キーを押して」= 何もしない、に設定してください",

            "approval.title": "召喚結果の承認",
            "approval.sources": "根拠",
            "approval.textEditable": "本文(編集可)",
            "approval.pasteInto": "貼り付け先",
            "approval.frontChanged": "⚠️ scan 時と最前面アプリが変わりました: %@。貼り付け先を確認してください",
            "approval.reject": "却下",
            "approval.pasteAnyway": "それでも貼る",
            "approval.approve": "承認",
            "approval.hint": "⏎ 承認 · ⇧⏎ 改行 · Esc 却下",

            "hud.cancel": "キャンセル",

            "settings.title": "設定",
            "settings.hotkey": "ホットキー",
            "settings.translateInto": "翻訳先の言語",
            "settings.language": "表示言語",
            "settings.fnNote": "システム設定 → キーボード → 「🌐キーを押して」= 何もしない、に設定してください",
            "settings.optionConflict": "ChatGPT アプリの既定のショートカットと衝突します",
            "settings.translateAuto": "自動(日⇄英)",
            "settings.translateNote": "translate 呪文(フォーム / LinkedIn / チャット / メール以外)で使われます",

            "menu.status": "状態…",
            "menu.settings": "設定…",
            "menu.quit": "終了",
            "approvalWindow.title": "承認",

            "error.pasteFailed": "貼り付けに失敗しました: %@",
            "error.transcriptionFailed": "文字起こしに失敗しました: %@",
            "error.summonFailed": "召喚に失敗しました: %@",
            "error.regenerationFailed": "再生成に失敗しました: %@",
            "error.chantTooShort": "詠唱が短すぎるか、録音できませんでした",
            "error.accessibilityRequired": "ホットキーの監視には Accessibility 権限が必要です",

            "hotkey.holdCmdEither": "⌘ 長押し(左右どちらでも)",
            "hotkey.holdRightCmd": "右⌘ 長押し",
            "hotkey.holdLeftCmd": "左⌘ 長押し",
            "hotkey.holdFn": "Fn(🌐)長押し",

            "pipeline.summoningStub": "召喚中…",
        ],
    ]
}
