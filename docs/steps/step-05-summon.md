# Step 05 — 召喚(`aishow summon`)

## 担当領域
- `Sources/aishow/Summon/TrueForgeClient.swift`: `TRUEFORGE_URL` に対し、セッション作成 → ターン送信 → イベントストリーム購読(SSE / WebSocket、実際のプロトコルは https://trueforge.dev の API 章を確認して `harness/SETUP.md` に記録)
- セッションキー: `site.domain`(なければ `app`)。`~/.aishow/sessions.json` に `domain → sessionId` を保持し、同じ会社への再詠唱は継続
- ターン内容: `workflow` 名 + `ContextPack` JSON + 詠唱テキスト(呪文の選択はハーネス側 Skill に任せる)
- イベント処理:
  - `tool_call` 開始/終了 → 「いま / 済み」として表示
  - 承認要求(`paste_to_cursor`)→ 本文・根拠 URL・貼り付け先を表示 → `y / e(編集) / n(理由)`
  - `y` → Step 03 の Paster を呼ぶ → 承認結果をハーネスに返す
  - `n` → 理由を同セッションに送って再生成
- CLI: `aishow summon [--chant "テキスト"]`(省略時は Step 04 の chant を内部で呼ぶ)= scan → chant → summon → pact → cast の一本道

## 禁止事項
- ハーネスを迂回して直接 OpenAI に生成させない(生成・調査・判断は TrueForge 側)
- 承認なしで Paster を呼ばない
- 最前面アプリが scan 時点と変わっていたら貼り付けない(警告して再確認)

## 検収基準
- [ ] Chrome で企業サイトの Contact ページを開き `aishow summon --chant "この会社に音声 SDK の話でコールドメッセージ"` → ターミナルに Bright Data の tool_call が流れ、承認プロンプトが出る
- [ ] `y` → フォームの Message 欄に英文が入る。送信されていない
- [ ] `n` + 理由 → 再生成された本文で再度承認プロンプト
- [ ] 同じドメインで 2 回目を実行 → 同じ sessionId が使われる(`sessions.json` で確認)
- [ ] TrueForge 未起動 → 起動コマンド(`make harness`)を案内して終了コード 69
