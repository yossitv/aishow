import SwiftUI

/// メニューバー Popover の常時表示。「いま / 待ち / 済み」の 3 行 + 直近 workflow。
struct StatusView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aishow").font(.headline)

            Divider()

            row(label: "いま", value: state.currentLine)
            row(label: "待ち", value: state.pendingLine.isEmpty ? "-" : state.pendingLine)
            row(
                label: "済み",
                value: state.lastCompleted?.summary ?? "-"
            )

            if let error = state.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if !state.permissions.accessibility || !state.permissions.microphone || !state.permissions.automation {
                Divider()
                permissionWarnings
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .leading)
            Text(value)
                .font(.body)
            Spacer()
        }
    }

    private var permissionWarnings: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("権限が不足しています").font(.caption).foregroundColor(.orange)
            if !state.permissions.accessibility {
                permissionButton(title: "Accessibility を許可…", pane: .accessibility)
            }
            if !state.permissions.microphone {
                permissionButton(title: "マイクを許可…", pane: .microphone)
            }
            if !state.permissions.automation {
                permissionButton(title: "Automation を許可…", pane: .automation)
            }
        }
    }

    private func permissionButton(title: String, pane: Permissions.SettingsPane) -> some View {
        Button(title) {
            Permissions.openSystemSettings(pane: pane)
        }
        .font(.caption)
    }
}
