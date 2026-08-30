import AppKit
import SwiftUI

/// 承認 Popover。根拠 URL / 本文(編集可)/ 貼り付け先を表示し、
/// 「承認」で編集後の本文を貼り付ける。Popover を閉じただけでは何もしない
/// (ボタンを押したときだけ `onApprove` / `onReject` が呼ばれる)。
struct ApprovalView: View {
    let approval: PendingApproval
    var onApprove: (String) -> Void
    var onReject: () -> Void

    @State private var editedText: String
    /// 最前面が scan 時と食い違う状態で 1 回警告を出した後、「それでも貼る」の 2 回目クリックを待っている。
    @State private var confirmedDespiteMismatch = false

    /// 承認 UI を出す直前の最前面アプリ・ウィンドウタイトルが scan 時と違えば警告する。
    /// 表示のたびに再評価しない(⏎ を受けるために Aishow 自身をアクティブにするので、その後は常に「自分」が最前面になる)。
    private let frontmostChanged: Bool

    init(approval: PendingApproval, onApprove: @escaping (String) -> Void, onReject: @escaping () -> Void) {
        self.approval = approval
        self.onApprove = onApprove
        self.onReject = onReject
        _editedText = State(initialValue: approval.proposal.text)

        let current = Frontmost.current()
        let selfName = NSRunningApplication.current.localizedName ?? "Aishow"
        if current.app == selfName {
            frontmostChanged = false // 自分の UI(HUD / popover)が最前面なだけ
        } else {
            frontmostChanged = current.app != approval.scannedApp || current.windowTitle != approval.pack.windowTitle
        }
    }

    /// ⏎ / Approve ボタン共通。最前面の食い違い警告が出ている間は 1 回目は同意扱い、2 回目で貼り付け。
    private func approveOrConfirm() {
        if frontmostChanged && !confirmedDespiteMismatch {
            confirmedDespiteMismatch = true
        } else {
            onApprove(editedText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approve summon result").font(.headline)

            if !approval.proposal.sources.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sources").font(.caption).foregroundColor(.secondary)
                    ForEach(approval.proposal.sources, id: \.self) { source in
                        Text(source).font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                }
            }

            Text("Text (editable)").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $editedText)
                .frame(height: 140)
                .border(Color.secondary.opacity(0.3))
                // テキスト欄にフォーカスがあっても ⏎ で承認できるようにする。改行は ⇧⏎ / ⌥⏎。
                .onKeyPress(phases: .down) { press in
                    guard press.key == .return else { return .ignored }
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) { return .ignored }
                    approveOrConfirm()
                    return .handled
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Paste into").font(.caption).foregroundColor(.secondary)
                Text("\(approval.pack.app) — \(approval.pack.windowTitle ?? "(no title)")")
                    .font(.caption)
            }

            if frontmostChanged && !confirmedDespiteMismatch {
                Text("⚠️ Front app changed since scan: \(approval.scannedApp). Please check the paste target.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let note = approval.proposal.note {
                Text(note).font(.caption2).foregroundColor(.secondary)
            }

            HStack {
                Button("Reject") { onReject() }
                    .keyboardShortcut(.cancelAction) // Esc
                Spacer()
                if frontmostChanged && !confirmedDespiteMismatch {
                    // 1 回目のクリックでは貼り付けず、警告に同意させるだけ(2 回目のクリックで実行)。
                    Button("Paste anyway") { confirmedDespiteMismatch = true }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Approve") { onApprove(editedText) }
                        .keyboardShortcut(.defaultAction) // ⏎(TextEditor にフォーカスが無いとき。あるときは onKeyPress が拾う)
                }
            }
            Text("⏎ Approve · ⇧⏎ New line · Esc Reject")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 360)
    }
}
