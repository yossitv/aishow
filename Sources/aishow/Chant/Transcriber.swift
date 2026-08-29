import Foundation

enum TranscriberError: Error {
    case missingApiKey
    case requestFailed(String)
}

struct SendError: Error {
    let message: String
}

/// OpenAI `POST /v1/audio/transcriptions` を `URLSession` のみで呼ぶ(SDK 不使用)。
/// 失敗時は `whisper-1` で 1 回だけ再試行する。API キーはログに出さない。
enum Transcriber {
    static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let fallbackModel = "whisper-1"

    static func transcribe(fileURL: URL) -> Result<String, TranscriberError> {
        guard let apiKey = Env.get("OPENAI_API_KEY"), !apiKey.isEmpty else {
            return .failure(.missingApiKey)
        }

        let model = Env.get("AISHOW_STT_MODEL") ?? "gpt-4o-transcribe"

        guard let audioData = try? Data(contentsOf: fileURL) else {
            return .failure(.requestFailed("音声ファイルを読み込めません"))
        }

        switch send(audioData: audioData, filename: fileURL.lastPathComponent, apiKey: apiKey, model: model) {
        case .success(let text):
            return .success(text)
        case .failure(let firstError):
            if model == fallbackModel {
                return .failure(.requestFailed(firstError.message))
            }
            switch send(audioData: audioData, filename: fileURL.lastPathComponent, apiKey: apiKey, model: fallbackModel) {
            case .success(let text):
                return .success(text)
            case .failure(let secondError):
                return .failure(.requestFailed("\(firstError.message); フォールバック(\(fallbackModel))も失敗: \(secondError.message)"))
            }
        }
    }

    private static func send(audioData: Data, filename: String, apiKey: String, model: String) -> Result<String, SendError> {
        let boundary = "aishow-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildBody(
            boundary: boundary,
            audioData: audioData,
            filename: filename,
            model: model
        )

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let resultError {
            return .failure(SendError(message: "network error: \(resultError.localizedDescription)"))
        }
        guard let http = resultResponse as? HTTPURLResponse else {
            return .failure(SendError(message: "no HTTP response"))
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = resultData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return .failure(SendError(message: "HTTP \(http.statusCode) \(bodyText.prefix(200))"))
        }
        guard let data = resultData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            return .failure(SendError(message: "unexpected response body"))
        }
        return .success(text)
    }

    private static func buildBody(boundary: String, audioData: Data, filename: String, model: String) -> Data {
        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        appendField(name: "language", value: "ja")
        appendField(name: "response_format", value: "json")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}
