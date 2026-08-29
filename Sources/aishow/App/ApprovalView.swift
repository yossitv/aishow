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

    init(approval: PendingApproval, onApprove: @escaping (String) -> Void, onReject: @escaping () -> Void) {
        self.approval = approval
        self.onApprove = onApprove
        self.onReject = onReject
        _editedText = State(initialValue: approval.proposal.text)
    }

    /// 承認しようとしている今この瞬間の最前面アプリ。scan 時と違えば警告する。
    private var frontmostChanged: Bool {
        Frontmost.current().app != approval.scannedApp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("召喚結果の承認").font(.headline)

            if !approval.proposal.sources.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("根拠 URL").font(.caption).foregroundColor(.secondary)
                    ForEach(approval.proposal.sources, id: \.self) { source in
                        Text(source).font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                }
            }

            Text("本文(編集可)").font(.caption).foregroundColor(.secondary)
            TextEditor(text: $editedText)
                .frame(height: 140)
                .border(Color.secondary.opacity(0.3))

            VStack(alignment: .leading, spacing: 2) {
                Text("貼り付け先").font(.caption).foregroundColor(.secondary)
                Text("\(approval.pack.app) — \(approval.pack.windowTitle ?? "(no title)")")
                    .font(.caption)
            }

            if frontmostChanged {
                Text("⚠️ 最前面アプリが索敵時(\(approval.scannedApp))と異なります。貼り付け先を確認してください。")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let note = approval.proposal.note {
                Text(note).font(.caption2).foregroundColor(.secondary)
            }

            HStack {
                Button("却下") { onReject() }
                Spacer()
                Button("承認") { onApprove(editedText) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 360)
    }
}
