import AishowCore
import Foundation

/// 索敵結果(`ContextPack` + `SiteDetection`)をひとまとめにした型。
struct ScanResult {
    var pack: ContextPack
    var site: SiteDetection
}

/// TrueForge との結線ポイント。Step 05 の実装はこのプロトコルに適合させて
/// `Pipeline.summonRunner` を差し替えるだけで良い(呼び出し側の変更は不要)。
protocol SummonRunner {
    /// - Parameters:
    ///   - pack: 索敵結果(ホットキー押下の瞬間に取得したもの)
    ///   - site: `pack` から判定した workflow
    ///   - chant: 詠唱(文字起こし済みテキスト)
    ///   - onEvent: 進捗イベント(「調査中…」等)を UI に伝えるコールバック。省略可
    /// - Returns: 承認待ちの `Proposal`
    func summon(
        pack: ContextPack,
        site: SiteDetection,
        chant: String,
        onEvent: @escaping (String) -> Void
    ) async throws -> Proposal
}

/// Step 05 の実装ができるまでのダミー。1 秒待って固定のダミー訳を返す。
struct StubSummonRunner: SummonRunner {
    func summon(
        pack: ContextPack,
        site: SiteDetection,
        chant: String,
        onEvent: @escaping (String) -> Void
    ) async throws -> Proposal {
        onEvent("調査中…")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return Proposal(
            sources: [],
            text: "(stub) \(chant) を英訳した風のダミーです",
            note: "stub"
        )
    }
}

/// 索敵〜召喚のパイプライン。ホットキーのハンドラから呼ばれる。
enum Pipeline {
    /// Step 05/07 の TrueForge クライアント。`AISHOW_STUB=1` のときだけダミーに差し替える。
    static var summonRunner: SummonRunner = {
        if Env.get("AISHOW_STUB") == "1" {
            return StubSummonRunner()
        }
        return TrueForgeSummonRunner()
    }()

    /// 索敵する。**自分の UI を出す前に呼ぶこと**(鉄則4)。
    static func scanNow() -> ScanResult {
        let frontmost = Frontmost.current()
        let browserInfo = BrowserURL.fetch(app: frontmost.app)
        let pageInfo = PageProbe.probe(app: frontmost.app)
        let selectedText = Selection.capture()

        let pack = ContextPack(
            app: frontmost.app,
            windowTitle: frontmost.windowTitle,
            url: browserInfo.url,
            pageTitle: browserInfo.pageTitle,
            selectedText: selectedText,
            focusedInput: pageInfo.focusedInput,
            hasFormTextarea: pageInfo.hasFormTextarea
        )
        let site = detect(pack)
        return ScanResult(pack: pack, site: site)
    }
}
