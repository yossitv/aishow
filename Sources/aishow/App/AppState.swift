import AishowCore
import Foundation

/// 承認待ちの一件。Popover(`ApprovalView`)に渡す。
struct PendingApproval: Identifiable {
    let id = UUID()
    var pack: ContextPack
    var site: SiteDetection
    var chant: String
    var proposal: Proposal
    /// scan 時点の最前面アプリ(承認時に食い違っていたら警告するため)
    var scannedApp: String
}

/// 完了した workflow の履歴 1 件(StatusView の「済み」に出す)。
struct CompletedItem: Identifiable {
    let id = UUID()
    var summary: String
    var completedAt: Date = Date()
}

/// メニューバー UI が観測する状態。`@MainActor` でメインスレッドからのみ更新する。
@MainActor
final class AppState: ObservableObject {
    /// 「いま」に出す 1 行(空なら待機中)
    @Published var currentLine: String = "待機中(\(HotKey.displayName) で詠唱)"
    /// 「待ち」に出す 1 行(承認待ちの workflow 名など)
    @Published var pendingLine: String = ""
    /// 「済み」の直近 1 件
    @Published var lastCompleted: CompletedItem?

    @Published var permissions: Permissions.Status = Permissions.check()

    /// 承認待ちの提案。nil でなければ承認 Popover を出す。
    @Published var pendingApproval: PendingApproval?

    /// 直近のエラーメッセージ(あれば Popover に出す)
    @Published var lastError: String?

    func refreshPermissions() {
        permissions = Permissions.check()
    }

    func setIdle() {
        currentLine = "待機中(\(HotKey.displayName) で詠唱)"
    }

    func setScanning() {
        currentLine = "索敵 ✔"
    }

    func setRecording() {
        currentLine = "詠唱中…"
    }

    func setTranscribing() {
        currentLine = "文字起こし中…"
    }

    func setSummoning(_ workflow: String, domain: String?) {
        let site = domain.map { "\(workflow) @ \($0)" } ?? workflow
        currentLine = "召喚 / \(site)"
        pendingLine = "調査中…"
    }

    func setEvent(_ text: String) {
        pendingLine = text
    }

    func setAwaitingApproval(_ approval: PendingApproval) {
        pendingApproval = approval
        currentLine = "承認待ち"
        pendingLine = "\(approval.site.workflow.rawValue) @ \(approval.site.domain ?? "-")"
    }

    func setCompleted(_ summary: String) {
        lastCompleted = CompletedItem(summary: summary)
        pendingApproval = nil
        pendingLine = ""
        setIdle()
    }

    func setError(_ message: String) {
        lastError = message
        currentLine = "エラー"
    }
}
