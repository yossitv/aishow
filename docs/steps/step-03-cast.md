# Step 03 — 発動(`aishow cast`)

## 担当領域
- `Sources/aishow/Cast/Paster.swift`:
  1. クリップボード退避(全 pasteboard type)
  2. テキスト書込
  3. 対象アプリを `NSRunningApplication.activate` で最前面化(引数 `--app`、省略時は現在の最前面)
  4. 最前面アプリが対象と一致することを確認(不一致なら中止して終了コード 65)
  5. `Cmd+V` を CGEvent で送信
  6. 300ms 後にクリップボード復元(失敗経路でも `defer` で復元)
- CLI: `echo "text" | aishow cast [--app "Google Chrome"] [--window-title "..."]`
- 実行ログ: `~/.aishow/log.jsonl` に `{ ts, app, windowTitle, chars, source: "cast" }` を追記(本文は保存しない)

## 禁止事項
- Enter / Return を送らない(送信は人間)
- 承認なしに呼ばれる経路を作らない(この CLI 自体は承認後に Step 05 から呼ばれる前提。README にその旨を明記)

## 検収基準
- [ ] TextEdit を開いて `echo "hello aishow" | aishow cast` → 本文に挿入される
- [ ] 実行前にクリップボードへ入れておいた画像/テキストが実行後も残っている
- [ ] `--app Slack` を指定して TextEdit を最前面にした状態で実行 → 何も貼られず終了コード 65
- [ ] `~/.aishow/log.jsonl` に 1 行追記され、本文は含まれない
