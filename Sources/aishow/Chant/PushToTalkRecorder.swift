import AVFoundation
import Foundation

/// ホットキー押下中だけ録音する push-to-talk 版レコーダー。
/// `Recorder`(Enter で止まる CLI 用)と違い、`start()` / `stop()` を明示的に呼ぶ。
final class PushToTalkRecorder {
    private var engine: AVAudioEngine?
    private var pcmBox: PushToTalkPCMBox?
    private var outFormat: AVAudioFormat?
    private var startedAt: Date?
    private var configObserver: NSObjectProtocol?
    private var isReconfiguring = false

    /// 1 秒未満の録音は詠唱として扱わない(ChantCommand と同じ閾値)。
    static let minimumSeconds: Double = 1.0

    /// マイクの許可状態。`.authorized` 以外なら `start()` は何もしない。
    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// 録音を開始する。既に録音中なら何もしない。
    func start() {
        guard engine == nil else { return }
        guard PushToTalkRecorder.microphoneAuthorized else {
            AppLog.write("録音開始できず: マイク許可なし(status=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue))")
            return
        }

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            AppLog.write("録音開始できず: 出力フォーマットを作れない")
            return
        }

        let engine = AVAudioEngine()
        // デバイス指定はフォーマット取得より先に行う(デバイスが変わるとフォーマットも変わるため)。
        AudioInputDevices.applyPreferredInputDevice(to: engine.inputNode)
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let box = PushToTalkPCMBox()

        guard installTap(on: engine, box: box, outFormat: outFormat) else {
            AppLog.write(String(format: "録音開始できず: 変換器を作れない(input=%@)", inputFormat.description))
            return
        }

        do {
            try engine.start()
        } catch {
            AppLog.write(String(format: "録音開始できず: engine.start 失敗 %@(input=%@)", error.localizedDescription, inputFormat.description))
            return
        }
        AppLog.write(String(format: "録音開始(input=%.0fHz/%dch)", inputFormat.sampleRate, inputFormat.channelCount))

        self.engine = engine
        self.pcmBox = box
        self.outFormat = outFormat
        self.startedAt = Date()

        observeConfigurationChanges(of: engine)
    }

    /// AVAudioEngineConfigurationChange 通知を処理する(Bluetooth マイクのサンプルレート切替など)。
    /// 通知ハンドラ内で直ちに再インストールすると、エンジン内部のグラフがまだ新しい
    /// ハードウェアフォーマットに切り替わりきっておらず `installTapOnNode` が
    /// `format.sampleRate == inputHWFormat.sampleRate` 例外で落ちることがあるため、
    /// メインキューへ一度ディスパッチしてから処理する(内部再構成が完了するのを待つ)。
    private func handleConfigurationChange(for changedEngine: AVAudioEngine) {
        guard !isReconfiguring else { return }
        isReconfiguring = true
        DispatchQueue.main.async { [weak self] in
            self?.performReconfiguration(for: changedEngine)
        }
    }

    /// 構成変更後は **エンジンを作り直す**。古いエンジンにタップを再設置すると、ノードのフォーマットが
    /// まだ新しい HW フォーマットに追従しておらず `installTapOnBus` が NSException(sampleRate 不一致)で落ちる
    /// (実機クラッシュ 2026-08-29 20:11)。新しいエンジンなら inputNode の outputFormat は現在の HW と一致する。
    private func performReconfiguration(for changedEngine: AVAudioEngine) {
        defer { isReconfiguring = false }
        guard let oldEngine = self.engine, oldEngine === changedEngine else { return }
        guard let box = pcmBox, let outFormat = outFormat else { return }

        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        configObserver = nil
        oldEngine.inputNode.removeTap(onBus: 0)
        oldEngine.stop()
        self.engine = nil // 再開に失敗した場合は stop() が nil を返し「録音なし」になる(クラッシュはしない)

        let newEngine = AVAudioEngine()
        AudioInputDevices.applyPreferredInputDevice(to: newEngine.inputNode)
        let newFormat = newEngine.inputNode.outputFormat(forBus: 0)
        guard newFormat.sampleRate > 0, newFormat.channelCount > 0 else {
            AppLog.write("録音: 入力構成変更後に有効な入力フォーマットが無い(デバイス無し?)")
            return
        }
        guard installTap(on: newEngine, box: box, outFormat: outFormat) else {
            AppLog.write("録音: 入力構成変更後の再インストールに失敗")
            return
        }
        do {
            try newEngine.start()
        } catch {
            AppLog.write(String(format: "録音: 入力構成変更後の engine.start 失敗 %@", error.localizedDescription))
            return
        }
        self.engine = newEngine
        observeConfigurationChanges(of: newEngine)
        AppLog.write(String(format: "録音: 入力構成変更 → エンジン再作成で再開(input=%.0fHz/%dch)", newFormat.sampleRate, newFormat.channelCount))
    }

    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange(for: engine)
        }
    }

    /// 入力タップをインストールする(初回起動・構成変更後の再起動の両方で使う)。
    /// タップは常にインストール時点の実際の `inputNode.outputFormat` から変換器を作る。
    private func installTap(on engine: AVAudioEngine, box: PushToTalkPCMBox, outFormat: AVAudioFormat) -> Bool {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // sampleRate 0 / 0ch(入力デバイス無し)で installTap すると NSException で落ちるため先に弾く。
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              AVAudioConverter(from: inputFormat, to: outFormat) != nil else {
            return false
        }

        let converterHolder = ConverterHolder(inputFormat: inputFormat, outFormat: outFormat)
        var firstBufferLogged = false
        let installedAt = Date()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            if !firstBufferLogged {
                firstBufferLogged = true
                let ms = Date().timeIntervalSince(installedAt) * 1000
                AppLog.write(String(format: "録音: 最初のバッファ到着 %.0fms", ms))
            }

            guard let converter = converterHolder.converter(for: buffer.format) else { return }

            let ratio = outFormat.sampleRate / max(buffer.format.sampleRate, 1)
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

            var providedInput = false
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
                if providedInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                providedInput = true
                outStatus.pointee = .haveData
                return buffer
            }

            // 入力ブロックが 2 回目に .noDataNow を返すため、status は .inputRanDry になることが多い。
            // その場合も converted には変換済みフレームが入っているので、.error 以外はすべて取り込む。
            if status != .error, converted.frameLength > 0, let channelData = converted.int16ChannelData {
                let frames = Int(converted.frameLength)
                let bytes = Data(bytes: channelData[0], count: frames * MemoryLayout<Int16>.size)
                box.append(bytes)
            }
        }

        return true
    }

    /// 録音を止め、WAV ファイルの URL を返す。1 秒未満、または録音していなかった場合は nil。
    func stop() -> URL? {
        guard let engine, let box = pcmBox, let startedAt else { return nil }

        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        configObserver = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        self.engine = nil
        self.pcmBox = nil
        self.outFormat = nil
        self.startedAt = nil

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed >= PushToTalkRecorder.minimumSeconds else { return nil }
        // 壁時計ではなく実データ量でも判定する(マイク入力が来ていない・変換に失敗した場合は空 WAV を送らない)。
        let minimumBytes = Int(16_000 * PushToTalkRecorder.minimumSeconds) * MemoryLayout<Int16>.size
        guard box.data.count >= minimumBytes else {
            AppLog.write(String(format: "録音データ不足: %d bytes(%.2f 秒押下)", box.data.count, elapsed))
            return nil
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("aishow", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let outURL = tmpDir.appendingPathComponent("chant-\(UUID().uuidString).wav")

        do {
            try WavUtil.write(pcmData: box.data, sampleRate: 16_000, to: outURL)
        } catch {
            return nil
        }
        return outURL
    }

    /// 録音中かどうか。
    var isRecording: Bool { engine != nil }
}

/// タップのクロージャ(リアルタイムスレッド)から安全に使うための AVAudioConverter ホルダー。
/// バッファの実フォーマットが直前のものと変わったら(Bluetooth 切替など)作り直す。
private final class ConverterHolder: @unchecked Sendable {
    private var currentInputFormat: AVAudioFormat
    private let outFormat: AVAudioFormat
    private var currentConverter: AVAudioConverter?
    private let lock = NSLock()

    init(inputFormat: AVAudioFormat, outFormat: AVAudioFormat) {
        self.currentInputFormat = inputFormat
        self.outFormat = outFormat
        self.currentConverter = AVAudioConverter(from: inputFormat, to: outFormat)
    }

    func converter(for format: AVAudioFormat) -> AVAudioConverter? {
        lock.lock()
        defer { lock.unlock() }
        if let converter = currentConverter, format.isEqual(currentInputFormat) {
            return converter
        }
        guard let newConverter = AVAudioConverter(from: format, to: outFormat) else {
            return nil
        }
        currentInputFormat = format
        currentConverter = newConverter
        return newConverter
    }
}

/// installTap のクロージャ(リアルタイムスレッド)から安全に PCM データを蓄積するための箱。
private final class PushToTalkPCMBox: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
