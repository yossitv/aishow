import Foundation

/// RIFF/WAV ヘッダを書き出し・読み取りするための小さなユーティリティ。
enum WavUtil {
    /// PCM (16bit mono) データを RIFF/WAV ヘッダ付きでファイルに書く。
    static func write(pcmData: Data, sampleRate: UInt32, to url: URL) throws {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let riffChunkSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(le32: riffChunkSize)
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(le32: 16)
        header.append(le16: 1) // PCM
        header.append(le16: channels)
        header.append(le32: sampleRate)
        header.append(le32: byteRate)
        header.append(le16: blockAlign)
        header.append(le16: bitsPerSample)
        header.append(contentsOf: Array("data".utf8))
        header.append(le32: dataSize)

        var full = header
        full.append(pcmData)
        try full.write(to: url, options: .atomic)
    }

    /// WAV ファイルの再生時間(秒)を data チャンクのサイズと byteRate から算出する。
    static func duration(ofWavAt url: URL) -> Double? {
        guard let data = try? Data(contentsOf: url), data.count >= 44 else { return nil }

        var offset = 12
        var byteRate: UInt32?
        var dataSize: UInt32?

        while offset + 8 <= data.count {
            let id = String(bytes: data[data.startIndex + offset ..< data.startIndex + offset + 4], encoding: .ascii) ?? ""
            let size = readLE32(data, at: offset + 4)

            if id == "fmt ", offset + 8 + 12 <= data.count {
                byteRate = readLE32(data, at: offset + 8 + 8)
            } else if id == "data" {
                dataSize = size
            }

            offset += 8 + Int(size) + (size % 2 == 1 ? 1 : 0)
        }

        guard let br = byteRate, br > 0, let ds = dataSize else { return nil }
        return Double(ds) / Double(br)
    }

    private static func readLE32(_ data: Data, at offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        let b0 = UInt32(data[base])
        let b1 = UInt32(data[base + 1])
        let b2 = UInt32(data[base + 2])
        let b3 = UInt32(data[base + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}

private extension Data {
    mutating func append(le32 value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func append(le16 value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
