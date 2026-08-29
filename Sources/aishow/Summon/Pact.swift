import Foundation

/// 承認ゲート(契約)。不可逆な貼り付けの前に、必ず人間の承認を経由させる。
/// TrueForge の MCP `paste_to_cursor` 経由の承認イベントではなく、ハーネスが返した
/// 「根拠 URL + 本文」の提案を CLI 側で提示して y/e/n を取る(`step-05-summon.md` の設計変更)。
enum Pact {
    enum Decision {
        case approve(text: String)
        case reject(reason: String)
    }

    /// 表示: workflow @ domain、根拠 URL、本文、貼り付け先(app / windowTitle)。
    /// - `y`: そのまま承認
    /// - `e`: 一時ファイルに本文を書いて `$EDITOR`(既定 vi)で開く。閉じたら読み直して再度この確認画面に戻る
    /// - `n`: 理由 1 行を読み、却下として返す
    /// `--dry-run` 用: 承認プロンプトを出さず、提案の表示だけを行う。
    static func display(
        workflow: String,
        domain: String?,
        proposal: Proposal,
        targetApp: String,
        targetWindowTitle: String?
    ) {
        printProposal(workflow: workflow, domain: domain, proposal: proposal, text: proposal.text, targetApp: targetApp, targetWindowTitle: targetWindowTitle)
    }

    static func confirm(
        workflow: String,
        domain: String?,
        proposal: Proposal,
        targetApp: String,
        targetWindowTitle: String?
    ) -> Decision {
        var currentText = proposal.text

        while true {
            printProposal(workflow: workflow, domain: domain, proposal: proposal, text: currentText, targetApp: targetApp, targetWindowTitle: targetWindowTitle)
            writeErr("[y] 承認して貼り付け  [e] 編集  [n] 却下(理由を送って再生成)")
            writeErr("> ", newline: false)

            guard let line = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces) else {
                return .reject(reason: "入力なし")
            }

            switch line.lowercased() {
            case "y":
                return .approve(text: currentText)
            case "e":
                if let edited = editInEditor(text: currentText) {
                    currentText = edited
                }
                // 編集後、再度確認画面に戻る(ループ継続)
            case "n":
                writeErr("却下の理由(1 行): ", newline: false)
                let reason = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces) ?? ""
                return .reject(reason: reason.isEmpty ? "(理由なし)" : reason)
            default:
                writeErr("y / e / n のいずれかを入力してください")
            }
        }
    }

    /// 現在の最前面アプリが scan 時点と変わっていないか確認する。変わっていたら警告して再確認する。
    /// 続行 = true、中止 = false。
    static func confirmFrontmostUnchanged(expectedApp: String, currentApp: String) -> Bool {
        guard expectedApp != currentApp else { return true }
        writeErr("")
        writeErr("警告: 最前面アプリが scan 時点(\(expectedApp))と変わっています(現在: \(currentApp))。")
        writeErr("このまま貼り付けますか? [y/n] > ", newline: false)
        let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces).lowercased()
        return answer == "y"
    }

    private static func editInEditor(text: String) -> String? {
        let editor = Env.get("EDITOR") ?? "vi"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("aishow-pact-\(UUID().uuidString).txt")

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            writeErr("編集用の一時ファイルを書き込めませんでした: \(error)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(editor) \(fileURL.path.replacingOccurrences(of: " ", with: "\\ "))"]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            writeErr("エディタの起動に失敗しました: \(error)")
            return nil
        }
        process.waitUntilExit()

        guard let edited = try? String(contentsOf: fileURL, encoding: .utf8) else {
            writeErr("編集後のファイルを読み込めませんでした")
            return nil
        }
        return edited.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func printProposal(
        workflow: String,
        domain: String?,
        proposal: Proposal,
        text: String,
        targetApp: String,
        targetWindowTitle: String?
    ) {
        writeErr("")
        writeErr("── 承認待ち ──────────────────────")
        writeErr("workflow: \(workflow) @ \(domain ?? "(no domain)")")
        writeErr("貼り付け先: \(targetApp)" + (targetWindowTitle.map { " — \($0)" } ?? ""))
        writeErr("根拠 URL:")
        if proposal.sources.isEmpty {
            writeErr("  (なし)")
        } else {
            for source in proposal.sources {
                writeErr("  - \(source)")
            }
        }
        if let note = proposal.note, !note.isEmpty {
            writeErr("note: \(note)")
        }
        writeErr("本文:")
        writeErr("----")
        writeErr(text)
        writeErr("----")
    }

    private static func writeErr(_ message: String, newline: Bool = true) {
        let text = newline ? message + "\n" : message
        FileHandle.standardError.write(text.data(using: .utf8)!)
    }
}
