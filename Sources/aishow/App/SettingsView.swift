import SwiftUI

/// 設定画面(メニューバー「Settings…」)。ホットキーと translate の宛先言語。
/// API キーは扱わない(`.env` / Keychain)。値は `UserDefaults` に即時保存し、ホットキーは `onHotKeyChanged` で再登録する。
struct SettingsView: View {
    /// ホットキー候補: (UserDefaults に保存する値, 表示名)
    static let hotKeyChoices: [(value: String, label: String)] = [
        ("cmd", "Hold ⌘ (either)"),
        ("rcmd", "Hold Right ⌘"),
        ("fn", "Hold Fn (🌐)"),
        ("option", "Option + Space"),
        ("control+option", "Control + Option + Space"),
    ]

    @State private var hotKey: String = UserDefaults.standard.string(forKey: HotKey.modifiersDefaultsKey) ?? "option"
    @State private var targetLanguage: String = Preferences.translateTargetLanguage
    let onHotKeyChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Picker("Hotkey", selection: $hotKey) {
                    ForEach(SettingsView.hotKeyChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .onChange(of: hotKey) { newValue in
                    UserDefaults.standard.set(newValue, forKey: HotKey.modifiersDefaultsKey)
                    onHotKeyChanged()
                }
                if hotKey == "fn" {
                    Text("Set System Settings → Keyboard → “Press 🌐 key to” = Do Nothing")
                        .font(.caption).foregroundColor(.secondary)
                } else if hotKey == "option" {
                    Text("Conflicts with the ChatGPT app’s default shortcut")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 4) {
                Picker("Translate into", selection: $targetLanguage) {
                    ForEach(Preferences.translateLanguages, id: \.self) { lang in
                        Text(lang == Preferences.translateAuto ? "Auto (JA ⇄ EN)" : lang).tag(lang)
                    }
                }
                .onChange(of: targetLanguage) { newValue in
                    Preferences.translateTargetLanguage = newValue
                }
                Text("Used by the translate workflow (anywhere that isn’t a form, LinkedIn, chat, or mail)")
                    .font(.caption).foregroundColor(.secondary)
            }
            .glassCard()
        }
        .padding(16)
        .frame(width: 340)
    }
}
