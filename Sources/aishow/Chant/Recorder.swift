import AVFoundation
import Foundation

enum RecorderError: Error {
    case permissionDenied
    case engineError(String)
}

/// `AVAudioEngine` でマイク入力を録音し、16kHz mono Int16 PCM の WAV に変換して
/// 一時ディレクトリ(`FileManager.default.temporaryDirectory/aishow/`)に書き出す。
enum Recorder {
    static let defaultMaxSeconds: Double = 30

    /// マイクから録音し、WAV ファイルの URL を返す。CLI では stdin の Enter で停止する。
    static func record() -> Result<URL, RecorderError> {
        switch requestMicrophoneAccess() {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        let maxSeconds: Double = {
            if let raw = Env.get("AISHOW_MAX_RECORD_SECONDS"), let value = Double(raw), value > 0 {
                return value
            }
            return defaultMaxSeconds
        }()

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("aishow", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.engineError("一時ディレクトリを作成できません: \(error.localizedDescription)"))
        }
        let outURL = tmpDir.appendingPathComponent("chant-\(UUID().uuidString).wav")

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // デバイス指定はフォーマット取得より先に行う(デバイスが変わるとフォーマットも変わるため)。
        AudioInputDevices.applyPreferredInputDevice(to: input)
        let inputFormat = input.outputFormat(forBus: 0)

        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            return .failure(.engineError("出力フォーマットの作成に失敗しました"))
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outFormat) else {
            return .failure(.engineError("AVAudioConverter の作成に失敗しました"))
        }

        let pcmBox = PCMBox()

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
                pcmBox.append(bytes)
            }
        }

        do {
            try engine.start()
        } catch {
            return .failure(.engineError("録音を開始できません: \(error.localizedDescription)"))
        }

        FileHandle.standardError.write("詠唱中… Enter で終了\n".data(using: .utf8)!)

        let stopSignal = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = readLine()
            stopSignal.signal()
        }
        _ = stopSignal.wait(timeout: .now() + maxSeconds)

        engine.stop()
        input.removeTap(onBus: 0)

        do {
            try WavUtil.write(pcmData: pcmBox.data, sampleRate: 16_000, to: outURL)
        } catch {
            return .failure(.engineError("WAV の書き込みに失敗しました: \(error.localizedDescription)"))
        }

        return .success(outURL)
    }

    private static func requestMicrophoneAccess() -> Result<Void, RecorderError> {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .success(())
        case .denied, .restricted:
            return .failure(.permissionDenied)
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                granted = ok
                sem.signal()
            }
            sem.wait()
            return granted ? .success(()) : .failure(.permissionDenied)
        @unknown default:
            return .failure(.permissionDenied)
        }
    }
}

/// installTap のクロージャ(リアルタイムスレッド)から安全に PCM データを蓄積するための箱。
private final class PCMBox: @unchecked Sendable {
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
