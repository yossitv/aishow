# Step 02 — 索敵・特定(`aishow scan`)

## 担当領域
- `Sources/aishow/Scan/`:
  - `Frontmost.swift`: `NSWorkspace.shared.frontmostApplication` を第一、`osascript`(System Events)を第二として突き合わせ。ウィンドウタイトルは System Events の `name of front window`
  - `BrowserURL.swift`: Chrome / Arc / Brave / Edge → `tell application "…" to get URL of active tab of front window` と `title`。Safari も同様。取れなければ nil(キーボードフォールバックは Step 06 以降)
  - `PageProbe.swift`: Chromium 系で `execute javascript` が許可されていれば `!!document.querySelector('form textarea')` と `document.activeElement.tagName` を取得。許可されていなければ両方 nil(URL ルールだけで判定する)
  - `Selection.swift`: クリップボード退避 → 空 → `Cmd+C`(CGEvent)→ 150ms → 読取 → **必ず復元**
- `Sources/AishowCore/Detect.swift`: `detect(_ pack: ContextPack) -> SiteDetection`。純粋関数。判定表は下記
- `Tests/AishowCoreTests/DetectTests.swift` + `Tests/Fixtures/context/*.json`(最低 8 ケース)
- CLI: `aishow scan [--json]` が `{ "pack": ContextPack, "site": SiteDetection }` を stdout に出す

## 判定表(上から順、最初に当たったもの)
| 条件 | kind | workflow |
|---|---|---|
| url が `linkedin.com/in/` or `linkedin.com/messaging/` | linkedin | linkedin_dm |
| app が Slack / Discord / Microsoft Teams / Messages | chat | casual_en |
| app が Mail、または url host が `mail.google.com` | mail | email_en |
| ブラウザ、かつ(url path が `contact|inquiry|get-in-touch|demo|sales|support|talk-to` を含む **or** `hasFormTextarea == true`) | website_form | website_form |
| ブラウザ、その他 | browser | translate |
| その他 | general | translate |
- `domain` は url の host から `www.` を除いたもの。url が無ければ nil

## 禁止事項
- 自分のウィンドウを出さない(CLI なので出ないが、Step 06 でも順序を守ること)
- 選択テキスト取得でクリップボードを汚したまま終了しない
- Accessibility 権限が無い場合はクラッシュせず、`selectedText: null` と stderr に権限案内を出す

## 検収基準
- [ ] `swift test` で DetectTests 全件通過(フィクスチャ 8 件以上、website_form の URL パス判定と textarea 判定を両方含む)
- [ ] Chrome で `https://example.com/contact` を開いて `aishow scan --json` → `site.kind == "website_form"`, `site.domain == "example.com"`
- [ ] Slack を最前面にして `aishow scan --json` → `site.workflow == "casual_en"`
- [ ] 任意のテキストを選択した状態で `aishow scan --json` → `selectedText` にその文字列、実行後のクリップボードが実行前と同じ
- [ ] 権限なし環境で実行してもプロセスが終了コード 0 で JSON を返す
