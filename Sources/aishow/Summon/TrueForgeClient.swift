import Foundation

/// TrueForge のイベントストリーム(SSE)で観測されるイベント。
/// `harness/trueforge-api.md` に記録した実機確認済みの形に合わせる。
/// 未知の type は `.other(type, raw)` として素通しする。
enum TrueForgeEvent {
    case turnCreated(turnId: String?)
    case modelMessageDelta(content: String?)
    case modelMessage(content: String?, toolCalls: [ToolCallSummary])
    case toolApprovalRequired(threadId: String?, toolCalls: [ApprovalToolCall])
    case toolResponse(toolCallId: String?)
    case turnDone(status: String, message: String?)
    case other(type: String, raw: [String: Any])

    struct ToolCallSummary {
        let id: String?
        let name: String?
    }

    struct ApprovalToolCall {
        let id: String
        let sourceEventId: String?
    }
}

/// TrueForge HTTP API クライアント(`harness/trueforge-api.md` のみを根拠にする)。
/// `URLSession` のみ、外部依存なし。CLI からの同期呼び出しに合わせ、内部は semaphore で待ち合わせる
/// (`Transcriber` と同じ流儀)。
enum TrueForgeClient {
    enum ClientError: Error, CustomStringConvertible {
        case connectionRefused
        case http(Int, String)
        case decode(String)
        case turnFailed(String)

        var description: String {
            switch self {
            case .connectionRefused:
                return "TrueForge に接続できません"
            case .http(let code, let body):
                return "HTTP \(code): \(body.prefix(300))"
            case .decode(let message):
                return "応答の解析に失敗しました: \(message)"
            case .turnFailed(let message):
                return "ターンが失敗しました: \(message)"
            }
        }
    }

    /// 認証ヘッダ注入口(現状のローカル standalone モードでは不要。将来トークンが要る場合に備える)。
    static var authorizationHeader: String? {
        Env.get("TRUEFORGE_TOKEN").map { "Bearer \($0)" }
    }

    static func baseURL() -> URL {
        let raw = Env.get("TRUEFORGE_URL") ?? "http://localhost:8790"
        return URL(string: raw) ?? URL(string: "http://localhost:8790")!
    }

    // MARK: - agents

    /// `aishow` という name の Saved Agent を作る/更新する。
    /// 既存なら PUT(manifest 全置き換え)、無ければ POST。
    static func ensureAgent(instructions: String, model: String, mcpServerNames: [String]) -> Swift.Result<Void, ClientError> {
        func manifest(mcpServers: [String]) -> [String: Any] {
            var manifest: [String: Any] = [
                "model": ["name": model],
                "instructions": instructions,
            ]
            if !mcpServers.isEmpty {
                manifest["mcp_servers"] = mcpServers.map { name -> [String: Any] in
                    [
                        "name": name,
                        "enable_tools": ["@all"],
                        "require_approval_for_tools": [],
                    ]
                }
            }
            return manifest
        }

        // 既存の aishow エージェントを探す。
        let existingId: String?
        switch getJSON(path: "/api/v1/agents") {
        case .success(let json):
            existingId = findAgentId(named: "aishow", in: json)
        case .failure(let error):
            return .failure(error)
        }

        func attempt(mcpServers: [String]) -> Swift.Result<Void, ClientError> {
            let body: [String: Any]
            let method: String
            let path: String
            if let existingId {
                method = "PUT"
                path = "/api/v1/agents/\(existingId)"
                body = ["manifest": manifest(mcpServers: mcpServers)]
            } else {
                method = "POST"
                path = "/api/v1/agents"
                body = ["name": "aishow", "manifest": manifest(mcpServers: mcpServers)]
            }
            return sendJSON(method: method, path: path, body: body).map { _ in () }
        }

        let result = attempt(mcpServers: mcpServerNames)
        if case .failure = result, !mcpServerNames.isEmpty {
            FileHandle.standardError.write(
                "aishow summon: Bright Data コネクタ未登録の可能性 — mcp_servers なしで再試行します\n".data(using: .utf8)!
            )
            return attempt(mcpServers: [])
        }
        return result
    }

    private static func findAgentId(named name: String, in json: Any) -> String? {
        guard let dict = json as? [String: Any], let data = dict["data"] as? [[String: Any]] else {
            return nil
        }
        return data.first { ($0["name"] as? String) == name }?["id"] as? String
    }

    // MARK: - sessions

    static func createSession(agentName: String) -> Swift.Result<String, ClientError> {
        let body: [String: Any] = ["agent": ["name": agentName]]
        switch sendJSON(method: "POST", path: "/api/v1/sessions", body: body) {
        case .success(let json):
            guard let dict = json as? [String: Any],
                  let data = dict["data"] as? [String: Any],
                  let id = data["id"] as? String else {
                return .failure(.decode("session response missing data.id"))
            }
            return .success(id)
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - turns (SSE)

    /// ターンを送信し、SSE イベントを逐次 `onEvent` に渡す。`turn.done` を受け取るまでブロックする。
    /// 戻り値は `turn.done` の `state.status`(`"done"` / `"error"` / `"cancelled"`)と、エラー時のメッセージ。
    @discardableResult
    static func sendTurn(
        sessionId: String,
        input: [[String: Any]],
        onEvent: @escaping (TrueForgeEvent) -> Void
    ) -> Swift.Result<Void, ClientError> {
        let body: [String: Any] = ["input": input]
        return streamTurn(path: "/api/v1/sessions/\(sessionId)/turns", body: body, onEvent: onEvent)
    }

    private static func streamTurn(
        path: String,
        body: [String: Any],
        onEvent: @escaping (TrueForgeEvent) -> Void
    ) -> Swift.Result<Void, ClientError> {
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.decode("failed to encode request body"))
        }

        var request = URLRequest(url: baseURL().appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let streamer = SSEStreamer(onEvent: onEvent)
        let session = URLSession(configuration: .default, delegate: streamer, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        streamer.wait()
        session.finishTasksAndInvalidate()

        if let connectionError = streamer.connectionError {
            let nsError = connectionError as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCannotConnectToHost {
                return .failure(.connectionRefused)
            }
            return .failure(.decode(connectionError.localizedDescription))
        }
        if let httpStatus = streamer.httpStatus, !(200...299).contains(httpStatus) {
            return .failure(.http(httpStatus, streamer.errorBodyText()))
        }
        if let failureMessage = streamer.turnFailureMessage {
            return .failure(.turnFailed(failureMessage))
        }
        return .success(())
    }

    // MARK: - plain JSON HTTP

    private static func getJSON(path: String) -> Swift.Result<Any, ClientError> {
        var request = URLRequest(url: baseURL().appendingPathComponent(path))
        request.httpMethod = "GET"
        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        return perform(request)
    }

    private static func sendJSON(method: String, path: String, body: [String: Any]) -> Swift.Result<Any, ClientError> {
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.decode("failed to encode request body"))
        }
        var request = URLRequest(url: baseURL().appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = authorizationHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData
        return perform(request)
    }

    private static func perform(_ request: URLRequest) -> Swift.Result<Any, ClientError> {
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
            let nsError = resultError as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCannotConnectToHost {
                return .failure(.connectionRefused)
            }
            return .failure(.decode(resultError.localizedDescription))
        }
        guard let http = resultResponse as? HTTPURLResponse else {
            return .failure(.decode("no HTTP response"))
        }
        let bodyText = resultData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard (200...299).contains(http.statusCode) else {
            return .failure(.http(http.statusCode, bodyText))
        }
        guard let data = resultData, let json = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.decode("invalid JSON body: \(bodyText.prefix(200))"))
        }
        return .success(json)
    }
}

/// `URLSessionDataDelegate` で SSE をインクリメンタルに読み、`data:` 行が揃うごとに
/// `TrueForgeEvent` にデコードして `onEvent` を呼ぶ。`turn.done` (or 接続終了) までブロックする。
private final class SSEStreamer: NSObject, URLSessionDataDelegate {
    private let onEvent: (TrueForgeEvent) -> Void
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private(set) var httpStatus: Int?
    private(set) var connectionError: Error?
    private(set) var turnFailureMessage: String?
    private var lastErrorBody = Data()
    private var didFinish = false

    init(onEvent: @escaping (TrueForgeEvent) -> Void) {
        self.onEvent = onEvent
    }

    func wait() {
        semaphore.wait()
    }

    func errorBodyText() -> String {
        String(data: lastErrorBody, encoding: .utf8) ?? ""
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        httpStatus = (response as? HTTPURLResponse)?.statusCode
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let status = httpStatus, !(200...299).contains(status) {
            lastErrorBody.append(data)
            return
        }
        buffer.append(data)
        processBuffer()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        connectionError = error
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        semaphore.signal()
    }

    /// バッファを SSE イベント区切り(空行)で分割し、`data:` 行を JSON デコードして処理する。
    private func processBuffer() {
        while let range = buffer.range(of: Data("\n\n".utf8)) {
            let chunk = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            handleChunk(chunk)
            if didFinish { return }
        }
    }

    private func handleChunk(_ chunk: Data) {
        guard let text = String(data: chunk, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("data:") else { continue }
            let jsonText = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard !jsonText.isEmpty,
                  let jsonData = jsonText.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = raw["type"] as? String else { continue }
            let event = decode(type: type, raw: raw)
            onEvent(event)
            if case .turnDone(let status, let message) = event {
                if status != "done" {
                    turnFailureMessage = message ?? "status=\(status)"
                }
                finish()
            }
        }
    }

    private func decode(type: String, raw: [String: Any]) -> TrueForgeEvent {
        switch type {
        case "turn.created":
            return .turnCreated(turnId: raw["turn_id"] as? String)
        case "model.message.delta":
            return .modelMessageDelta(content: raw["content"] as? String)
        case "model.message":
            let toolCalls = ((raw["tool_calls"] as? [[String: Any]]) ?? []).map {
                TrueForgeEvent.ToolCallSummary(id: $0["id"] as? String, name: ($0["name"] as? String) ?? (($0["function"] as? [String: Any])?["name"] as? String))
            }
            return .modelMessage(content: raw["content"] as? String, toolCalls: toolCalls)
        case "tool.approval_required":
            let threadId = raw["thread_id"] as? String
            let toolCalls = ((raw["tool_calls"] as? [[String: Any]]) ?? []).compactMap { entry -> TrueForgeEvent.ApprovalToolCall? in
                guard let id = entry["id"] as? String else { return nil }
                return TrueForgeEvent.ApprovalToolCall(id: id, sourceEventId: entry["source_event_id"] as? String)
            }
            return .toolApprovalRequired(threadId: threadId, toolCalls: toolCalls)
        case "tool.response":
            return .toolResponse(toolCallId: raw["tool_call_id"] as? String)
        case "turn.done":
            let state = raw["state"] as? [String: Any]
            let status = (state?["status"] as? String) ?? "unknown"
            let message = state?["message"] as? String
            return .turnDone(status: status, message: message)
        default:
            return .other(type: type, raw: raw)
        }
    }
}
