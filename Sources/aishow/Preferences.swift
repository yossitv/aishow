import Foundation

/// 常駐アプリ / CLI 共通のユーザー設定(`UserDefaults`)。API キーは扱わない(それは Env / Keychain)。
enum Preferences {
    /// translate 呪文の宛先言語。`"auto"` は従来どおり「日本語なら英語、英語なら日本語」。
    static let translateTargetLanguageKey = "translateTargetLanguage"
    static let translateAuto = "auto"

    /// 設定画面で選べる宛先言語(表示名 = 呪文に渡す値。モデルが読めれば良いので英語名)。
    static let translateLanguages: [String] = [
        translateAuto,
        "English", "Japanese", "Chinese (Simplified)", "Chinese (Traditional)", "Korean",
        "Spanish", "French", "German", "Portuguese", "Italian", "Vietnamese", "Thai", "Indonesian", "Hindi", "Arabic",
    ]

    static var translateTargetLanguage: String {
        get { UserDefaults.standard.string(forKey: translateTargetLanguageKey) ?? translateAuto }
        set { UserDefaults.standard.set(newValue, forKey: translateTargetLanguageKey) }
    }

    /// 録音に使う入力デバイスの CoreAudio UID。nil / 空文字 = システム既定(automatic)。
    /// AirPods が既定入力だと録音の瞬間に Bluetooth が HFP プロファイルへ落ち、
    /// 音楽の音質が悪化するので、内蔵マイクなど特定デバイスに固定できるようにする。
    static let microphoneDeviceUIDKey = "microphoneDeviceUID"

    static var microphoneDeviceUID: String? {
        get {
            let value = UserDefaults.standard.string(forKey: microphoneDeviceUIDKey)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: microphoneDeviceUIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: microphoneDeviceUIDKey)
            }
        }
    }

    /// 召喚本文に足すオプション。workflow ごとに必要なものだけ返す(呪文が読む key 名)。
    static func summonOptions(workflow: String) -> [String: String] {
        guard workflow == "translate" else { return [:] }
        let lang = translateTargetLanguage
        return lang == translateAuto ? [:] : ["target_language": lang]
    }
}
