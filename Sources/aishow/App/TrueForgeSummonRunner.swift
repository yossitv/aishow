import AishowCore
import Foundation

/// `SummonRunner` の本実装。`SummonCommand`(CLI)の流れ
/// (ensureAgent → session → ターン送信 → SSE を「いま/済み」として `onEvent` に流す → Proposal 抽出)
/// を `TrueForgeSummon` の共有関数を通じて再利用する。TrueForge 未起動なら `throw` し、
/// `MenuBarApp` はそのエラーメッセージ(「TrueForge が起動していません(make harness)」)を表示する。
struct TrueForgeSummonRunner: SummonRunner {
    func summon(
        pack: ContextPack,
        site: SiteDetection,
        chant: String,
        onEvent: @escaping (String) -> Void
    ) async throws -> Proposal {
        let sessionId = try ensureSessionOrThrow(site: site, pack: pack)
        let message = TrueForgeSummon.buildTurnBody(
            workflow: site.workflow.rawValue,
            pack: pack,
            chant: chant,
            options: Preferences.summonOptions(workflow: site.workflow.rawValue) // translate の宛先言語など
        )
        return try await send(sessionId: sessionId, message: message, onEvent: onEvent)
    }

    /// 却下 → 再生成。`MenuBarApp` の却下ハンドラから呼ぶ(同セッションに「却下: <理由>。作り直して」を送る)。
    func regenerate(
        pack: ContextPack,
        site: SiteDetection,
        reason: String,
        onEvent: @escaping (String) -> Void
    ) async throws -> Proposal {
        let sessionId = try ensureSessionOrThrow(site: site, pack: pack)
        return try await send(sessionId: sessionId, message: "却下: \(reason)。作り直して", onEvent: onEvent)
    }

    private func ensureSessionOrThrow(site: SiteDetection, pack: ContextPack) throws -> String {
        switch TrueForgeSummon.ensureSession(site: site, pack: pack) {
        case .success(let sessionId):
            return sessionId
        case .failure(let error):
            throw error
        }
    }

    private func send(
        sessionId: String,
        message: String,
        onEvent: @escaping (String) -> Void
    ) async throws -> Proposal {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                switch TrueForgeSummon.sendAndCollect(sessionId: sessionId, message: message, onEvent: onEvent) {
                case .success(let proposal):
                    continuation.resume(returning: proposal)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
