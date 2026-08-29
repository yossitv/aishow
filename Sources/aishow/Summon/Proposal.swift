import Foundation

/// 呪文(harness/spells)の出力契約: エージェントの最終回答に含まれる ```json フェンス 1 個。
/// `{"sources": [url...], "text": "本文", "note": "調査不足なら理由"}`
struct Proposal: Codable {
    var sources: [String]
    var text: String
    var note: String?
}

enum ProposalParser {
    enum Failure: Error {
        case noJSONBlock
        case decode(String)
    }

    /// エージェントの最終メッセージ本文(蓄積した `model.message` / `model.message.delta` の content)から
    /// 最後の ```json ブロックを取り出して decode する。
    static func parse(fromFinalMessage message: String) -> Swift.Result<Proposal, Failure> {
        guard let block = lastJSONFence(in: message) else {
            return .failure(.noJSONBlock)
        }
        guard let data = block.data(using: .utf8) else {
            return .failure(.decode("not utf8"))
        }
        do {
            let proposal = try JSONDecoder().decode(Proposal.self, from: data)
            return .success(proposal)
        } catch {
            return .failure(.decode("\(error)"))
        }
    }

    private static func lastJSONFence(in text: String) -> String? {
        let fenceMarker = "```json"
        guard let startRange = text.range(of: fenceMarker, options: .backwards) else {
            return nil
        }
        let afterFence = text[startRange.upperBound...]
        guard let endRange = afterFence.range(of: "```") else {
            return nil
        }
        let body = afterFence[afterFence.startIndex..<endRange.lowerBound]
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
