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
    @State private var microphoneUID: String = Preferences.microphoneDeviceUID ?? ""
    @State private var microphoneDevices: [AudioInputDevice] = AudioInputDevices.list()
    let onHotKeyChanged: () -> Void

    /// 「System default」の表示名(現在の既定入力が分かれば括弧書きで添える)。
    private var systemDefaultLabel: String {
        if let name = AudioInputDevices.defaultInputName() {
            return "System default (automatic) — currently: \(name)"
        }
        return "System default (automatic)"
    }

    /// 保存済み UID が一覧に無い(デバイスが抜かれている)場合に表示用の choices へ足しておく。
    private var microphoneChoices: [AudioInputDevice] {
        var devices = microphoneDevices
        if !microphoneUID.isEmpty, !devices.contains(where: { $0.uid == microphoneUID }) {
            devices.append(AudioInputDevice(uid: microphoneUID, name: "\(microphoneUID) (not connected)"))
        }
        return devices
    }

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

            VStack(alignment: .leading, spacing: 4) {
                Picker("Microphone", selection: $microphoneUID) {
                    Text(systemDefaultLabel).tag("")
                    ForEach(microphoneChoices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .onChange(of: microphoneUID) { newValue in
                    Preferences.microphoneDeviceUID = newValue
                }
                Text("Pick the built-in microphone to keep AirPods on the high-quality audio profile while listening to music.")
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
