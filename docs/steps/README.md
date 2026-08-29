# 実装 Step(発注書)

各 Step = 1 PR = Qodo `/agentic_review` を通してマージ。順番どおりに進める(後の Step は前の Step の成果物に依存)。
各発注書は **担当領域 / 禁止事項 / 検収基準(機械的に確認できるもの)** を持つ。VoiceInk-japanese の `docs/orders/` 方式。

| Step | 名前 | 成果物 | 依存 |
|---|---|---|---|
| [00](step-00-scaffold.md) | 骨組み | リポジトリ設定、Swift Package、.gitignore、Qodo 設定 | — |
| [01](step-01-harness.md) | ハーネス | TrueForge ローカル起動、OpenAI モデル、Bright Data MCP、呪文(Skill) | 00 |
| [02](step-02-scan-detect.md) | 索敵・特定 | `aishow scan`: 最前面アプリ・URL・選択テキスト → ContextPack + SiteDetection | 00 |
| [03](step-03-cast.md) | 発動 | `aishow cast`: カーソル位置への貼り付け(クリップボード復元) | 02 |
| [04](step-04-chant.md) | 詠唱 | `aishow chant`: 録音 → OpenAI STT → テキスト | 00 |
| [05](step-05-summon.md) | 召喚 | `aishow summon`: TrueForge API でセッション・ターン・イベント・承認 → cast | 01, 02, 03, 04 |
| [06](step-06-menubar.md) | 常駐 | `Aishow.app`: メニューバー常駐、グローバルホットキー、状態表示、承認ポップオーバー | 05 |

ゴール(Step 06 完了時)の体験:
> 企業サイトの Contact フォームを開く → `Option+Space` を押しながら日本語で詠唱 → メニューバーに「索敵 ✔ → website_form @ acme.com → 召喚 → 調査中(Bright Data)…」→ 承認ポップオーバー → 承認 → Message 欄に英文が入る。送信は人間。

## 共通ルール
- 不可逆操作(貼り付け・送信・スクレイパー approve)は必ず承認ゲートの後
- API キーは `.env` / 環境変数のみ。`.env` は gitignore 済み
- OS 操作(osascript / CGEvent / NSPasteboard)は `Sources/aishow/` 側、純粋ロジックは `Sources/AishowCore/` 側。Core にはテストを付ける
- 最前面アプリの取得は **自分の UI を出す前に** 行う(KashinAI の教訓)
- クリップボードを触ったら、失敗経路でも必ず復元する
