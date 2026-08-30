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

    /// 内蔵マイクの CoreAudio UID(Apple Silicon / Intel の MacBook で共通)。
    static let builtInMicrophoneUID = "BuiltInMicrophoneDevice"

    /// 現在のシステム既定入力デバイスの ID。
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    /// デバイスの転送方式(kAudioDeviceTransportType*)。
    static func transportType(of deviceID: AudioDeviceID) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// Bluetooth(AirPods 等)の入力か。HFP ⇄ A2DP の切替でサンプルレートが変わり、A2DP 側ではマイクデータが
    /// 来ないため、録音用途では内蔵マイクへ逃がす(2026-08-29 実機: 24kHz ⇄ 48kHz を往復して 0 bytes)。
    static func isBluetooth(_ deviceID: AudioDeviceID) -> Bool {
        guard let type = transportType(of: deviceID) else { return false }
        return type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE
    }

    /// push-to-talk 録音(`AVCaptureSession`)で使う入力デバイスを決める。
    /// 優先順: Preferences で選ばれたデバイス → システム既定。ただし選ばれた/既定のデバイスが **Bluetooth**
    /// (AirPods 等)で内蔵マイクがあるときは内蔵マイクを使う(HFP ⇄ A2DP 切替で録音が途切れる・音楽の音質が落ちる)。
    static func captureDeviceForRecording() -> AVCaptureDevice? {
        let preferredUID = Preferences.microphoneDeviceUID.flatMap { $0.isEmpty ? nil : $0 }

        var chosen: AVCaptureDevice?
        var label = "システム既定"
        if let uid = preferredUID {
            if let device = AVCaptureDevice(uniqueID: uid) {
                chosen = device
                label = "指定デバイス(\(device.localizedName))"
            } else {
                AppLog.write("マイク設定: 指定デバイスが見つからずシステム既定にフォールバック(uid=\(uid))")
            }
        }
        if chosen == nil {
            chosen = AVCaptureDevice.default(for: .audio)
        }
        guard let candidate = chosen else { return nil }

        // AVCaptureDevice.uniqueID は CoreAudio の UID と同じ(実機確認: BuiltInMicrophoneDevice / xx-xx-…:input)。
        if let id = deviceID(forUID: candidate.uniqueID), isBluetooth(id),
           let builtIn = AVCaptureDevice(uniqueID: builtInMicrophoneUID), builtIn.uniqueID != candidate.uniqueID {
            AppLog.write("マイク設定: \(label) は Bluetooth 入力のため内蔵マイクを使用(HFP 切替で録音が途切れるのを回避)")
            return builtIn
        }
        return candidate
    }

    /// `AVAudioEngine` の inputNode に録音用の入力デバイスを割り当てる。
    /// 優先順: Preferences で選ばれたデバイス → システム既定。ただし選ばれた/既定のデバイスが **Bluetooth** で
    /// 内蔵マイクがあるときは内蔵マイクを使う。未検出・設定失敗の場合はシステム既定へフォールバックし、
    /// 録音自体は止めない(呼び出し側は特にエラーハンドリング不要)。
    static func applyPreferredInputDevice(to inputNode: AVAudioInputNode) {
        let preferredUID = Preferences.microphoneDeviceUID.flatMap { $0.isEmpty ? nil : $0 }

        var target: AudioDeviceID?
        var label = "システム既定"
        if let uid = preferredUID {
            if let id = deviceID(forUID: uid) {
                target = id
                label = "指定デバイス(uid=\(uid))"
            } else {
                AppLog.write("マイク設定: 指定デバイスが見つからずシステム既定にフォールバック(uid=\(uid))")
            }
        }
        if target == nil {
            target = defaultInputDeviceID()
        }
        guard var chosen = target else { return }

        var explicitlySet = preferredUID != nil && target != defaultInputDeviceID()
        if isBluetooth(chosen), let builtIn = deviceID(forUID: builtInMicrophoneUID), builtIn != chosen {
            AppLog.write("マイク設定: \(label) は Bluetooth 入力のため内蔵マイクを使用(HFP 切替で録音が途切れるのを回避)")
            chosen = builtIn
            explicitlySet = true
        }
        guard explicitlySet || preferredUID != nil else { return } // 既定のままで良い

        guard let audioUnit = inputNode.audioUnit else {
            AppLog.write("マイク設定: audioUnit が取得できずシステム既定にフォールバック")
            return
        }
        var mutableDeviceID = chosen
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
            AppLog.write("マイク設定: 入力デバイスを指定(id=\(chosen), \(label))")
        }
    }
}
