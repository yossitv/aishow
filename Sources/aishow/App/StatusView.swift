import SwiftUI

/// メニューバー Popover の常時表示。「いま / 待ち / 済み」の 3 行 + 直近 workflow。
struct StatusView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aishow").font(.headline)

            Divider()

            row(label: "Now", value: state.currentLine)
            row(label: "Pending", value: state.pendingLine.isEmpty ? "-" : state.pendingLine)
            row(
                label: "Done",
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

            if HotKey.isFnMode {
                // Fn(🌐)単独モードの注意書き: システム設定側で🌐キーの既定動作を無効化しないと奪われる。
                Text("Fn (🌐) mode: Set System Settings → Keyboard → “Press 🌐 key to” = Do Nothing")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
            Text("Permissions needed").font(.caption).foregroundColor(.orange)
            if !state.permissions.accessibility {
                permissionButton(title: "Allow Accessibility…", pane: .accessibility)
            }
            if !state.permissions.microphone {
                permissionButton(title: "Allow Microphone…", pane: .microphone)
            }
            if !state.permissions.automation {
                permissionButton(title: "Allow Automation…", pane: .automation)
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
