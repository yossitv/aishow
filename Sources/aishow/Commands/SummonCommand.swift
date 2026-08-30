import AishowCore
import Foundation

/// `aishow summon [--chant "テキスト"] [--dry-run]`
/// scan → chant → TrueForge(ensureAgent → session → turn) → Pact(承認) → cast の一本道。
enum SummonCommand {
    static func run(_ args: [String]) -> Int32 {
        var chantText: String?
        var dryRun = false

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--chant":
                i += 1
                if i < args.count { chantText = args[i] }
            case "--dry-run":
                dryRun = true
            default:
                writeErr("aishow summon: unknown option: \(args[i])")
                return 64
            }
            i += 1
        }

        // 1. scan(鉄則4: 自分の UI を出す前に索敵する)
        let scanned = Scan.perform()

        // 2. --chant が無ければ Chant で録音 → テキスト
        let text: String
        if let chantText {
            text = chantText
        } else {
            switch Chant.capture() {
            case .success(let captured):
                text = captured
            case .failure(let failure):
                writeErr(failure.message)
                return failure.exitCode
            }
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            writeErr("aishow summon: 詠唱テキストが空です")
            return 64
        }

        // 3〜4. TrueForge 未起動なら案内して終了、起動していれば ensureAgent → セッション
        let sessionId: String
        switch TrueForgeSummon.ensureSession(site: scanned.site, pack: scanned.pack) {
        case .success(let id):
            sessionId = id
        case .failure(.connectionRefused):
            writeErr("aishow summon: TrueForge に接続できません。`make harness` で起動してください。")
            return 69
        case .failure(let error):
            writeErr("aishow summon: \(error)")
            return 1
        }

        // 5. ターン送信 → ストリーム表示
        let turnBody = TrueForgeSummon.buildTurnBody(workflow: scanned.site.workflow.rawValue, pack: scanned.pack, chant: text, options: Preferences.summonOptions(workflow: scanned.site.workflow.rawValue))

        func sendAndCollect(message: String) -> Swift.Result<Proposal, TrueForgeSummon.SummonError> {
            TrueForgeSummon.sendAndCollect(sessionId: sessionId, message: message, onEvent: { writeErr($0) })
        }

        var currentProposal: Proposal
        switch sendAndCollect(message: turnBody) {
        case .success(let parsed):
            currentProposal = parsed
        case .failure(.connectionRefused):
            writeErr("aishow summon: TrueForge に接続できません。`make harness` で起動してください。")
            return 69
        case .failure(let error):
            writeErr("aishow summon: \(error)")
            return 1
        }

        if currentProposal.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            writeErr("aishow summon: 調査不足のため貼り付けを見送ります: \(currentProposal.note ?? "(理由なし)")")
            return 1
        }

        // --dry-run は提案の表示までで終了(貼り付けない)
        if dryRun {
            Pact.display(
                workflow: scanned.site.workflow.rawValue,
                domain: scanned.site.domain,
                proposal: currentProposal,
                targetApp: scanned.pack.app,
                targetWindowTitle: scanned.pack.windowTitle
            )
            writeErr("(--dry-run: 承認・貼り付けはスキップ)")
            return 0
        }

        // 6. Pact(承認)→ y なら cast
        var retriesLeft = 2
        while true {
            let decision = Pact.confirm(
                workflow: scanned.site.workflow.rawValue,
                domain: scanned.site.domain,
                proposal: currentProposal,
                targetApp: scanned.pack.app,
                targetWindowTitle: scanned.pack.windowTitle
            )

            switch decision {
            case .approve(let finalText):
                let currentApp = Frontmost.current().app
                guard Pact.confirmFrontmostUnchanged(expectedApp: scanned.pack.app, currentApp: currentApp) else {
                    writeErr("aishow summon: 中止しました(最前面アプリの変化を確認できず)")
                    return 1
                }
                do {
                    let result = try Paster.paste(text: finalText, appName: scanned.pack.app, windowTitle: scanned.pack.windowTitle)
                    CastLog.append(app: result.appName, windowTitle: result.windowTitle, chars: result.chars, source: "summon")
                    return 0
                } catch let failure as Paster.Failure {
                    writeErr(Paster.message(for: failure))
                    return Paster.exitCode(for: failure)
                } catch {
                    writeErr("aishow summon: 貼り付けに失敗しました: \(error)")
                    return 1
                }

            case .reject(let reason):
                guard retriesLeft > 0 else {
                    writeErr("aishow summon: 再生成の上限に達しました。中止します。")
                    return 1
                }
                retriesLeft -= 1
                let retryMessage = "却下: \(reason)。作り直して"
                switch sendAndCollect(message: retryMessage) {
                case .success(let parsed):
                    currentProposal = parsed
                    if currentProposal.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        writeErr("aishow summon: 調査不足のため貼り付けを見送ります: \(currentProposal.note ?? "(理由なし)")")
                        return 1
                    }
                case .failure(.connectionRefused):
                    writeErr("aishow summon: TrueForge に接続できません。`make harness` で起動してください。")
                    return 69
                case .failure(let error):
                    writeErr("aishow summon: \(error)")
                    return 1
                }
            }
        }
    }

    private static func writeErr(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
