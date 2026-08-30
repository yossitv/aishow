import SwiftUI

/// 設定画面(メニューバー「Settings…」)。ホットキーと translate の宛先言語。
/// API キーは扱わない(`.env` / Keychain)。値は `UserDefaults` に即時保存し、ホットキーは `onHotKeyChanged` で再登録する。
struct SettingsView: View {
    /// ホットキー候補: (UserDefaults に保存する値, 表示名の L10n キー)。
    /// "Option + Space" 系はキー入力の見た目そのものなので両言語共通(L10n を通さない)。
    static let hotKeyChoices: [(value: String, labelKey: String?, literalLabel: String?)] = [
        ("cmd", "hotkey.holdCmdEither", nil),
        ("rcmd", "hotkey.holdRightCmd", nil),
        ("fn", "hotkey.holdFn", nil),
        ("option", nil, "Option + Space"),
        ("control+option", nil, "Control + Option + Space"),
    ]

    @ObservedObject private var l10n = L10n.shared

    @State private var hotKey: String = UserDefaults.standard.string(forKey: HotKey.modifiersDefaultsKey) ?? "option"
    @State private var targetLanguage: String = Preferences.translateTargetLanguage
    @State private var uiLanguage: UILanguage = Preferences.uiLanguage
    let onHotKeyChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("settings.title")).font(.headline)

            Picker(L10n.t("settings.language"), selection: $uiLanguage) {
                ForEach(UILanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .onChange(of: uiLanguage) { newValue in
                L10n.shared.language = newValue
            }

            VStack(alignment: .leading, spacing: 4) {
                Picker(L10n.t("settings.hotkey"), selection: $hotKey) {
                    ForEach(SettingsView.hotKeyChoices, id: \.value) { choice in
                        Text(choice.labelKey.map { L10n.t($0) } ?? choice.literalLabel ?? choice.value).tag(choice.value)
                    }
                }
                .onChange(of: hotKey) { newValue in
                    UserDefaults.standard.set(newValue, forKey: HotKey.modifiersDefaultsKey)
                    onHotKeyChanged()
                }
                if hotKey == "fn" {
                    Text(L10n.t("settings.fnNote"))
                        .font(.caption).foregroundColor(.secondary)
                } else if hotKey == "option" {
                    Text(L10n.t("settings.optionConflict"))
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Picker(L10n.t("settings.translateInto"), selection: $targetLanguage) {
                    ForEach(Preferences.translateLanguages, id: \.self) { lang in
                        Text(lang == Preferences.translateAuto ? L10n.t("settings.translateAuto") : lang).tag(lang)
                    }
                }
                .onChange(of: targetLanguage) { newValue in
                    Preferences.translateTargetLanguage = newValue
                }
                Text(L10n.t("settings.translateNote"))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
