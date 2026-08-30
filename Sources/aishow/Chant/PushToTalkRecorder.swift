import AVFoundation
import CoreMedia
import Foundation

/// ホットキー押下中だけ録音する push-to-talk 版レコーダー。
/// `Recorder`(Enter で止まる CLI 用)と違い、`start()` / `stop()` を明示的に呼ぶ。
///
/// 実装は `AVCaptureSession` + `AVCaptureAudioDataOutput`。`AVAudioEngine` は inputNode が
/// **システム既定の入力デバイスに追従してしまい**、AudioUnit にデバイスを指定しても構成変更のたびに
/// 既定(AirPods)へ戻る・AirPods の HFP ⇄ A2DP 切替で止まる・作り直すたびに AirPods のマイクが ON になる、
/// という問題が実機で再現した(2026-08-29 20:18〜20:26 のログ)。`AVCaptureSession` はデバイスを直接指定でき、
/// 既定デバイスに触らない。16kHz / mono / Int16 への変換も `audioSettings` に任せる。
final class PushToTalkRecorder: NSObject {
    private var session: AVCaptureSession?
    private var pcmBox: PushToTalkPCMBox?
    private var startedAt: Date?
    private var firstBufferLogged = false
    private let sampleQueue = DispatchQueue(label: "com.openhome.aishow.ptt-audio")

    /// STT に渡す形式(OpenAI transcriptions は 16kHz mono で十分)。
    static let outputSampleRate: Double = 16_000

    /// 1 秒未満の録音は詠唱として扱わない(ChantCommand と同じ閾値)。
    static let minimumSeconds: Double = 1.0

    /// マイクの許可状態。`.authorized` 以外なら `start()` は何もしない。
    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// 録音を開始する。既に録音中なら何もしない。
    func start() {
        guard session == nil else { return }
        guard PushToTalkRecorder.microphoneAuthorized else {
            AppLog.write("録音開始できず: マイク許可なし(status=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue))")
            return
        }
        guard let device = AudioInputDevices.captureDeviceForRecording() else {
            AppLog.write("録音開始できず: 入力デバイスが見つからない")
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                AppLog.write("録音開始できず: 入力を追加できない(\(device.localizedName))")
                return
            }
            session.addInput(input)
        } catch {
            AppLog.write("録音開始できず: AVCaptureDeviceInput 失敗 \(error.localizedDescription)(\(device.localizedName))")
            return
        }

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: PushToTalkRecorder.outputSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else {
            AppLog.write("録音開始できず: 出力を追加できない")
            return
        }
        session.addOutput(output)
        session.commitConfiguration()

        let box = PushToTalkPCMBox()
        firstBufferLogged = false
        self.pcmBox = box
        self.session = session
        self.startedAt = Date()

        session.startRunning() // 同期(100〜300ms)。scan より先に呼ばれるので UI には影響しない
        AppLog.write("録音開始(device=\(device.localizedName) → \(Int(PushToTalkRecorder.outputSampleRate))Hz/1ch/Int16)")
    }

    /// 録音を止め、WAV ファイルの URL を返す。1 秒未満、または録音していなかった場合は nil。
    func stop() -> URL? {
        guard let session, let box = pcmBox, let startedAt else { return nil }

        session.stopRunning()

        self.session = nil
        self.pcmBox = nil
        self.startedAt = nil

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed >= PushToTalkRecorder.minimumSeconds else { return nil }
        // 壁時計ではなく実データ量でも判定する(マイク入力が来ていない場合は空 WAV を送らない)。
        let minimumBytes = Int(PushToTalkRecorder.outputSampleRate * PushToTalkRecorder.minimumSeconds) * MemoryLayout<Int16>.size
        let data = box.data
        guard data.count >= minimumBytes else {
            AppLog.write(String(format: "録音データ不足: %d bytes(%.2f 秒押下)", data.count, elapsed))
            return nil
        }
        AppLog.write(String(format: "録音停止: %.2f 秒押下 / %.2f 秒分のデータ", elapsed, Double(data.count) / (PushToTalkRecorder.outputSampleRate * 2)))

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("aishow", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let outURL = tmpDir.appendingPathComponent("chant-\(UUID().uuidString).wav")

        do {
            try WavUtil.write(pcmData: data, sampleRate: UInt32(PushToTalkRecorder.outputSampleRate), to: outURL)
        } catch {
            return nil
        }
        return outURL
    }

    /// 録音中かどうか。
    var isRecording: Bool { session != nil }
}

extension PushToTalkRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let box = pcmBox, let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return }

        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        guard status == kCMBlockBufferNoErr else { return }
        box.append(data)

        if !firstBufferLogged {
            firstBufferLogged = true
            let ms = startedAt.map { Date().timeIntervalSince($0) * 1000 } ?? 0
            var desc = ""
            if let fd = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                desc = String(format: " %.0fHz/%dch/%dbit", asbd.mSampleRate, asbd.mChannelsPerFrame, asbd.mBitsPerChannel)
            }
            AppLog.write(String(format: "録音: 最初のバッファ到着 %.0fms%@", ms, desc))
        }
    }
}

/// キャプチャキューから安全に PCM データを蓄積するための箱。
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
