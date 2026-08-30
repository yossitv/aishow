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
    @State private var microphoneUID: String = Preferences.microphoneDeviceUID ?? ""
    @State private var microphoneDevices: [AudioInputDevice] = AudioInputDevices.list()
    @State private var uiLanguage: UILanguage = Preferences.uiLanguage
    let onHotKeyChanged: () -> Void

    /// 「System default」の表示名(現在の既定入力が分かれば括弧書きで添える)。
    private var systemDefaultLabel: String {
        if let name = AudioInputDevices.defaultInputName() {
            return "\(L10n.t("settings.microphoneDefault")) — \(L10n.t("settings.microphoneCurrently", name))"
        }
        return L10n.t("settings.microphoneDefault")
    }

    /// 保存済み UID が一覧に無い(デバイスが抜かれている)場合に表示用の choices へ足しておく。
    private var microphoneChoices: [AudioInputDevice] {
        var devices = microphoneDevices
        if !microphoneUID.isEmpty, !devices.contains(where: { $0.uid == microphoneUID }) {
            devices.append(AudioInputDevice(uid: microphoneUID, name: "\(microphoneUID) (\(L10n.t("settings.microphoneNotConnected")))"))
        }
        return devices
    }

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
            .glassCard()

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
            .glassCard()

            VStack(alignment: .leading, spacing: 4) {
                Picker(L10n.t("settings.microphone"), selection: $microphoneUID) {
                    Text(systemDefaultLabel).tag("")
                    ForEach(microphoneChoices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .onChange(of: microphoneUID) { newValue in
                    Preferences.microphoneDeviceUID = newValue
                }
                Text(L10n.t("settings.microphoneNote"))
                    .font(.caption).foregroundColor(.secondary)
            }
            .glassCard()
            .onAppear {
                microphoneDevices = AudioInputDevices.list()
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
