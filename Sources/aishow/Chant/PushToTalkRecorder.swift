import AVFoundation
import Foundation

/// ホットキー押下中だけ録音する push-to-talk 版レコーダー。
/// `Recorder`(Enter で止まる CLI 用)と違い、`start()` / `stop()` を明示的に呼ぶ。
final class PushToTalkRecorder {
    private var engine: AVAudioEngine?
    private var pcmBox: PushToTalkPCMBox?
    private var outFormat: AVAudioFormat?
    private var startedAt: Date?

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

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outFormat) else {
            AppLog.write(String(format: "録音開始できず: 変換器を作れない(input=%@)", inputFormat.description))
            return
        }

        let box = PushToTalkPCMBox()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let ratio = outFormat.sampleRate / max(inputFormat.sampleRate, 1)
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
    }

    /// 録音を止め、WAV ファイルの URL を返す。1 秒未満、または録音していなかった場合は nil。
    func stop() -> URL? {
        guard let engine, let box = pcmBox, let startedAt else { return nil }

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
