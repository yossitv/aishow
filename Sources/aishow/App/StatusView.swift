import SwiftUI

/// メニューバー Popover の常時表示。「いま / 待ち / 済み」の 3 行 + 直近 workflow。
struct StatusView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aishow").font(.headline)

            row(label: L10n.t("status.now"), value: state.currentLine)
                .glassCard(tint: .blue)
            row(label: L10n.t("status.pending"), value: state.pendingLine.isEmpty ? L10n.t("status.dash") : state.pendingLine)
                .glassCard(tint: .orange)
            row(
                label: L10n.t("status.done"),
                value: state.lastCompleted?.summary ?? L10n.t("status.dash")
            )
            .glassCard(tint: .green)

            if let error = state.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .glassCard(tint: .red)
            }

            if !state.permissions.accessibility || !state.permissions.microphone || !state.permissions.automation {
                permissionWarnings
                    .glassCard(tint: .orange)
            }

            if HotKey.isFnMode {
                // Fn(🌐)単独モードの注意書き: システム設定側で🌐キーの既定動作を無効化しないと奪われる。
                Text(L10n.t("status.fnModeNote"))
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
            Text(L10n.t("status.permissionsNeeded")).font(.caption).foregroundColor(.orange)
            if !state.permissions.accessibility {
                permissionButton(title: L10n.t("status.allowAccessibility"), pane: .accessibility)
            }
            if !state.permissions.microphone {
                permissionButton(title: L10n.t("status.allowMicrophone"), pane: .microphone)
            }
            if !state.permissions.automation {
                permissionButton(title: L10n.t("status.allowAutomation"), pane: .automation)
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
