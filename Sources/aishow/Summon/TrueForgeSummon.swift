import AishowCore
import Foundation

/// TrueForge との結線ロジックの共有実体。`SummonCommand`(CLI)と `TrueForgeSummonRunner`(常駐アプリ)
/// の両方から呼ばれる(`ensureAgent → session → turn → Proposal` の一本道)。
enum TrueForgeSummon {
    enum SummonError: Error, CustomStringConvertible {
        case connectionRefused
        case other(String)

        var description: String {
            switch self {
            case .connectionRefused:
                return "TrueForge が起動していません(make harness)"
            case .other(let message):
                return message
            }
        }
    }

    /// ensureAgent(instructions/model/mcp) → セッション取得(ドメイン単位で継続)。
    static func ensureSession(site: SiteDetection, pack: ContextPack) -> Swift.Result<String, SummonError> {
        let model = Env.get("AISHOW_MODEL") ?? "openai/gpt-5.2"
        let mcpServers = (Env.get("AISHOW_MCP_SERVERS") ?? "brightdata")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let instructions = SpellBook.buildInstructions()

        switch TrueForgeClient.ensureAgent(instructions: instructions, model: model, mcpServerNames: mcpServers) {
        case .success:
            break
        case .failure(.connectionRefused):
            return .failure(.connectionRefused)
        case .failure(let error):
            return .failure(.other("エージェントの準備に失敗しました: \(error)"))
        }

        let sessionKey = SessionStore.key(domain: site.domain, app: pack.app)
        if let existing = SessionStore.get(key: sessionKey) {
            // Qodo #7-8: 保存済み sessionId が TrueForge 側で失効(404)していたら新規作成し直す。
            switch TrueForgeClient.getSession(id: existing) {
            case .success:
                return .success(existing)
            case .failure(.http(404, _)):
                break
            case .failure(.connectionRefused):
                return .failure(.connectionRefused)
            case .failure(let error):
                return .failure(.other("セッション確認に失敗しました: \(error)"))
            }
        }

        switch TrueForgeClient.createSession(agentName: "aishow") {
        case .success(let id):
            SessionStore.set(key: sessionKey, sessionId: id)
            return .success(id)
        case .failure(.connectionRefused):
            return .failure(.connectionRefused)
        case .failure(let error):
            return .failure(.other("セッション作成に失敗しました: \(error)"))
        }
    }

    static func buildTurnBody(workflow: String, pack: ContextPack, chant: String) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let contextJSON: String
        if let data = try? encoder.encode(pack), let str = String(data: data, encoding: .utf8) {
            contextJSON = str
        } else {
            contextJSON = "{}"
        }
        return "workflow: \(workflow)\ncontext: \(contextJSON)\nchant: \(chant)"
    }

    /// ターンを送信し、SSE イベントを「いま: …」「済み: …」の文字列として `onEvent` に流す。
    /// 最終メッセージから ```json フェンスを取り出して `Proposal` にする。
    static func sendAndCollect(
        sessionId: String,
        message: String,
        onEvent: @escaping (String) -> Void
    ) -> Swift.Result<Proposal, SummonError> {
        var collectedMessages: [String] = []
        let result = TrueForgeClient.sendTurn(
            sessionId: sessionId,
            input: [["type": "user.message", "content": message]],
            onEvent: { event in handle(event: event, collectedMessages: &collectedMessages, onEvent: onEvent) }
        )
        switch result {
        case .failure(.connectionRefused):
            return .failure(.connectionRefused)
        case .failure(let error):
            return .failure(.other("\(error)"))
        case .success:
            break
        }

        let joined = collectedMessages.joined(separator: "\n")
        switch ProposalParser.parse(fromFinalMessage: joined) {
        case .success(let parsed):
            return .success(parsed)
        case .failure:
            return .failure(.other("提案(```json ブロック)を解析できませんでした。応答: \(joined.prefix(400))"))
        }
    }

    private static func handle(event: TrueForgeEvent, collectedMessages: inout [String], onEvent: (String) -> Void) {
        switch event {
        case .modelMessage(let content, let toolCalls):
            if let content, !content.isEmpty {
                collectedMessages.append(content)
            }
            for toolCall in toolCalls {
                onEvent("いま: \(toolCall.name ?? toolCall.id ?? "tool")")
            }
        case .toolResponse(let toolCallId):
            onEvent("済み: \(toolCallId ?? "tool")")
        case .toolApprovalRequired(_, let toolCalls):
            for toolCall in toolCalls {
                onEvent("いま: (承認待ち) \(toolCall.id)")
            }
        case .turnDone(let status, let message):
            if status != "done" {
                onEvent("済み: turn.done status=\(status) \(message ?? "")")
            }
        default:
            break
        }
    }
}
