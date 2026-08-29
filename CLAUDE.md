# Aishow — 開発規約(エージェント・人間共通)

「声で詠唱すると、AI エージェントが現れて仕事をする」macOS アプリ。Agent Harness Hackathon(2026-08-29 SF)。
要件: `docs/idea.md`。実装は `docs/steps/` の発注書どおりに Step 単位で進め、1 Step = 1 PR = Qodo レビュー。進捗は `docs/kanban.xlsx`(`python3 scripts/kanban.py` で更新)。

## 構成
- `Sources/AishowCore/` 純粋ロジック(OS 依存なし、テスト必須)— ContextPack / SiteDetection / detect()
- `Sources/aishow/` CLI + 常駐アプリ。`Commands/*Command.swift` が各サブコマンド、OS 操作(osascript / CGEvent / NSPasteboard / AVAudioEngine)はここ
- `harness/` TrueForge の設定手順(`SETUP.md`)と呪文(`spells/*.md` = workflow ごとの Skill)
- `Tests/` XCTest。`Tests/Fixtures/context/*.json` はフィクスチャドリブン
- ビルド: `swift build` / `swift test` / `make app`(`dist/Aishow.app`、ad-hoc 署名)

## 鉄則
1. 不可逆操作(他アプリへの貼り付け・送信・スクレイパー approve)は**承認ゲートの後**にしか呼ばない。`cast` は承認済みテキストしか受け取らない前提
2. API キーは環境変数 / `.env` / Keychain。コード・ログ・フィクスチャに書かない
3. クリップボードを触ったら失敗経路でも必ず復元(`defer`)
4. 最前面アプリの取得は**自分の UI を出す前**に行う
5. 生成・調査・判断は TrueForge(ハーネス)側。CLI/アプリは「入出力 + サイト特定 → workflow 分岐」だけ。ハーネスを迂回して直接 OpenAI に生成させない(STT は例外)
6. 外部 SDK を足さない(`URLSession` / `Foundation` で足りる)。依存追加は発注書に明記されたものだけ
7. Enter / Return は送らない。送信は人間

## workflow(呪文)一覧
| workflow | いつ | 呪文ファイル |
|---|---|---|
| website_form | ブラウザで問い合わせフォーム(URL パス `contact|inquiry|demo|sales|support|talk-to` or `<form textarea>`) | `harness/spells/website_form.md` |
| linkedin_dm | linkedin.com/in/ or /messaging/ | `harness/spells/linkedin_dm.md` |
| casual_en | Slack / Discord / Teams / Messages | `harness/spells/casual_en.md` |
| email_en | Mail / mail.google.com | `harness/spells/email_en.md` |
| translate | それ以外 | `harness/spells/translate.md` |

## Bright Data scrapers(再利用。作り直さないこと)
- 会社サイト構造化(companyName / tagline / products[] / latestNews): `bdata scraper run <COLLECTOR_ID> https://<domain>/ --pretty`(collector: **未作成 — Step 01 で作成し、ここに id を記入**)
- 壊れたら `bdata scraper heal <COLLECTOR_ID> "<症状: 例 products が空>"` → diff 確認 → **承認ゲート** → `bdata scraper approve <COLLECTOR_ID>`
- 失敗時は collector_id と response_id を必ず標準出力に出す
- MCP(生 Markdown): `scrape_as_markdown` で `https://{domain}/`, `/about`, `/products`, `/blog|/news`。`search_engine` で `"{domain}" news 2026`
- ログイン必須・有料壁は取らない。個人データはセッション外に保存しない

## コミット・PR
- ブランチ `step-0N-<name>`、PR タイトル `Step 0N: <name>`。PR 本文に発注書の検収基準をチェックリストで貼る
- Qodo `/agentic_review` の High は全件対応してからマージ
- コミット末尾: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
