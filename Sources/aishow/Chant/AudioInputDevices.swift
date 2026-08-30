import AVFoundation
import CoreAudio
import Foundation

/// 設定画面のピッカーに出す 1 台の入力デバイス。
struct AudioInputDevice: Identifiable, Hashable {
    let uid: String
    let name: String
    var id: String { uid }
}

/// 入力デバイスの列挙と、CoreAudio 側の UID ⇔ AudioDeviceID 解決をまとめたユーティリティ。
/// (AirPods 接続中に既定入力が Bluetooth になり、録音の瞬間に HFP へ落ちて音楽の音質が
/// 悪化する問題への対策として、録音専用の入力デバイスを選べるようにする)
enum AudioInputDevices {
    /// 現在利用可能な入力デバイス一覧(名前が引ける AVCaptureDevice ベース)。
    static func list() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { AudioInputDevice(uid: $0.uniqueID, name: $0.localizedName) }
    }

    /// CoreAudio の UID からデバイス ID を引く。デバイスが抜かれている場合などは nil。
    ///
    /// UID は **qualifier** として渡す(`AudioValueTranslation` 構造体を渡す旧形式は現行 macOS で
    /// `kAudioHardwareBadPropertySizeError('!siz')` になり、常に「見つからない」扱いになっていた)。
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        var deviceID = AudioDeviceID(0)
        var uidCF = uid as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status: OSStatus = withUnsafeMutablePointer(to: &uidCF) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPtr,
                &size,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown, deviceID != 0 else { return nil }
        return deviceID
    }

    /// 現在の既定入力デバイスの名前(「System default (currently: AirPods Pro)」の表示用)。
    static func defaultInputName() -> String? {
        var deviceID = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceSize, &deviceID)
        guard deviceStatus == noErr, deviceID != 0 else { return nil }

        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let nameStatus: OSStatus = withUnsafeMutablePointer(to: &name) { namePtr in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, UnsafeMutableRawPointer(namePtr))
        }
        guard nameStatus == noErr else { return nil }
        return name as String
    }

    /// `AVAudioEngine` の inputNode に、Preferences で選ばれたデバイスを割り当てる。
    /// 未設定・デバイス未検出・設定失敗のいずれの場合もシステム既定へフォールバックし、
    /// 録音自体は止めない(呼び出し側は特にエラーハンドリング不要)。
    static func applyPreferredInputDevice(to inputNode: AVAudioInputNode) {
        guard let uid = Preferences.microphoneDeviceUID, !uid.isEmpty else { return }
        guard let deviceID = deviceID(forUID: uid) else {
            AppLog.write("マイク設定: 指定デバイスが見つからずシステム既定にフォールバック(uid=\(uid))")
            return
        }
        guard let audioUnit = inputNode.audioUnit else {
            AppLog.write("マイク設定: audioUnit が取得できずシステム既定にフォールバック")
            return
        }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            AppLog.write("マイク設定: AudioUnitSetProperty 失敗(status=\(status))、システム既定にフォールバック")
        } else {
            AppLog.write("マイク設定: 入力デバイスを指定(uid=\(uid))")
        }
    }
}
