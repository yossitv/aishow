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
    @Published var currentLine: String = "Ready — hold \(HotKey.displayName) to chant"
    /// 「待ち」に出す 1 行(承認待ちの workflow 名など)
    @Published var pendingLine: String = ""
    /// 「済み」の直近 1 件
    @Published var lastCompleted: CompletedItem?

    @Published var permissions: Permissions.Status = Permissions.check()

    /// 承認待ちの提案。nil でなければ承認 Popover を出す。
    @Published var pendingApproval: PendingApproval?

    /// 直近のエラーメッセージ(あれば Popover に出す)
    @Published var lastError: String?

    /// scan〜summon が進行中、または承認待ちかどうか(ホットキーの多重起動防止用。Qodo #7-5)。
    @Published var isBusy: Bool = false

    func refreshPermissions() {
        permissions = Permissions.check()
    }

    func setIdle() {
        currentLine = "Ready — hold \(HotKey.displayName) to chant"
        isBusy = false
    }

    func setScanning() {
        currentLine = "Scanned ✔"
        isBusy = true
    }

    func setRecording() {
        currentLine = "Chanting…"
    }

    func setTranscribing() {
        currentLine = "Transcribing…"
    }

    func setSummoning(_ workflow: String, domain: String?) {
        let site = domain.map { "\(workflow) @ \($0)" } ?? workflow
        currentLine = "Summoning / \(site)"
        pendingLine = "Summoning…"
    }

    func setEvent(_ text: String) {
        pendingLine = text
    }

    func setAwaitingApproval(_ approval: PendingApproval) {
        pendingApproval = approval
        currentLine = "Awaiting approval"
        pendingLine = "\(approval.site.workflow.rawValue) @ \(approval.site.domain ?? "-")"
    }

    /// 貼り付け完了。HUD に「Pasted into X ✔」を 2.5 秒見せてから待機に戻す(承認後に何も変わらないと分からないため)。
    func setCompleted(_ summary: String) {
        lastCompleted = CompletedItem(summary: summary)
        pendingApproval = nil
        pendingLine = ""
        lastError = nil
        currentLine = "Pasted into \(summary) ✔ — review and press Enter yourself"
        isBusy = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, !self.isBusy, self.pendingApproval == nil else { return }
            self.setIdle()
        }
    }

    /// × ボタン等でセッションを取り消した。エラーも消して待機に戻す。
    func setCancelled() {
        pendingApproval = nil
        lastError = nil
        currentLine = "Cancelled"
        isBusy = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.isBusy, self.pendingApproval == nil else { return }
            self.setIdle()
        }
    }

    func setError(_ message: String) {
        lastError = message
        currentLine = "Error"
        isBusy = false
    }
}
