# Aishow(詠唱)

> 声で詠唱すると、AI エージェントが現れて仕事をする。

企業サイトの問い合わせフォームを開いたまま `Option+Space` を押して日本語で「この会社に、うちの音声 SDK の話でコールドメッセージ」と言う。
ローカルの **TrueForge** エージェントが召喚され、いま開いているサイトを特定し、**Bright Data MCP** でそのサイトを調査、**OpenAI** モデルがあなたの文体で英文を書く。**承認**した内容だけがフォームのカーソル位置に入る。送信は人間。

Agent Harness Hackathon(San Francisco, 2026-08-29)提出作品。

```
shortcut key + voice ─▶ TrueForge agent(local)─▶ サイト / サービス特定 ─▶ workflow 分岐
                                                       │
                       ┌───────────────────────────────┼──────────────────────────┐
                       ▼                               ▼                          ▼
                website form(問い合わせ)          LinkedIn / Slack 等          その他(翻訳)
                Bright Data MCP でサイト取得
                → OpenAI がコールドメッセージ
                → 承認 → フォームに挿入
```

## 使い方
```bash
cp .env.example .env                 # OPENAI_API_KEY, BRIGHTDATA_API_KEY を入れる
make harness                         # 別ターミナルで TrueForge を起動(http://localhost:8790)
./scripts/setup-harness.sh           # OpenAI モデル + Bright Data ホスト型 MCP を TrueForge に登録(冪等)
swift build && swift test

# CLI(1 コマンドずつ確認できる)
.build/debug/aishow scan --json                       # 索敵: 最前面アプリ・URL・選択テキスト → workflow 判定
.build/debug/aishow chant --file Tests/Fixtures/audio/sample-ja.wav   # 詠唱: OpenAI STT
echo "hello" | .build/debug/aishow cast --app com.apple.TextEdit      # 発動: 貼り付け(承認後にのみ使う)
.build/debug/aishow summon --chant "この会社に音声 SDK の話でコールドメッセージ"   # 召喚 → 承認(y/e/n)→ 発動
.build/debug/aishow summon --dry-run --chant "..."   # 提案の表示まで(貼り付けなし)
.build/debug/aishow flame --seconds 4                 # (検収用) 画面の縁に炎を N 秒表示して消える

# メニューバー常駐(ホットキー Option+Space を押しながら話す)
make app && open dist/Aishow.app
```
初回起動でマイク / Accessibility / Automation の許可が要る(メニューバーの「状態…」に導線)。`aishow` エージェントは初回 `summon` 時に `harness/spells/*.md` から自動作成・更新される。

詠唱中(ホットキーを押している間)は画面の縁に炎が出る。メニューの「詠唱中に炎の枠を表示」のチェックを外す、または `defaults write com.openhome.aishow flameOverlayEnabled -bool false` で OFF にできる(既定 ON)。

## 動作の流れ
1. **索敵**: ホットキー押下の瞬間に最前面アプリ・ウィンドウタイトル・ブラウザ URL・選択テキストを取得(自分の UI を出す前に)
2. **特定**: `detect()`(純粋関数・フィクスチャテスト)が `website_form / linkedin_dm / casual_en / email_en / translate` を決める
3. **詠唱**: push-to-talk 録音 → OpenAI `gpt-4o-transcribe`
4. **召喚**: TrueForge のセッション(ドメインごとに永続)へ workflow + ContextPack + 詠唱を送る。エージェントが Bright Data MCP でサイトを調査し `{sources, text}` を返す。SSE を「いま / 待ち / 済み」として表示
5. **契約**: 承認ポップオーバー(根拠 URL・本文編集・貼り付け先・最前面アプリ変化の警告)。却下理由は同セッションに返して再生成
6. **発動**: クリップボード退避 → Cmd+V → 復元。**Enter は送らない**

## 実機で通した例(2026-08-29)
Chrome で `https://brightdata.com/contact` を開いて詠唱「この会社に、うちの音声SDKの話でコールドメッセージ」→ `website_form @ brightdata.com` → TrueForge 上の gpt-5.2 が Bright Data MCP を 14 回呼び、次を返した:

> **sources**: https://docs.brightdata.com/datasets/scrapers/concepts/web-scraper-api-vs-diy
> **text**: I noticed Bright Data's Web Scraper API highlights 1000+ pre-built, maintained scrapers—impressive coverage. We've built a voice SDK that helps teams add fast, reliable speech UX (streaming STT/TTS, latency tuning, and tooling) to products and internal apps. If voice could complement any of your dashboards or developer tooling, I'd love to share a quick 15-minute overview—who's best to speak with?

## ドキュメント
- [docs/idea.md](docs/idea.md) — 要件
- [docs/steps/](docs/steps/README.md) — 実装 Step(発注書)。1 Step = 1 PR = Qodo レビュー
- [docs/kanban.xlsx](docs/kanban.xlsx) — 進捗(`python3 scripts/kanban.py`)
- [harness/SETUP.md](harness/SETUP.md) — TrueForge / OpenAI / Bright Data の設定
- [harness/trueforge-api.md](harness/trueforge-api.md) — 実機で確認した TrueForge の HTTP/SSE プロトコル(snake_case、error は turn.done 内、MCP は remote URL 専用)
- PR 一覧(すべて Qodo `/agentic_review` 済み): [#1 harness](https://github.com/yossitv/aishow/pull/1) · [#2 scan](https://github.com/yossitv/aishow/pull/2) · [#3 cast](https://github.com/yossitv/aishow/pull/3) · [#4 chant](https://github.com/yossitv/aishow/pull/4) · [#5 summon](https://github.com/yossitv/aishow/pull/5) · [#6 menubar](https://github.com/yossitv/aishow/pull/6)
- [CLAUDE.md](CLAUDE.md) — 開発規約・Bright Data collector のピン留め

## スポンサー製品の使いどころ
| 製品 | 役割 |
|---|---|
| TrueForge(TrueFoundry) | エージェントハーネス本体。モデル・MCP 接続・承認ゲート・サブエージェント・セッション永続 |
| Bright Data | 開いているサイトのライブ取得(MCP)+ 会社サイト構造化 collector(`CLAUDE.md` にピン留め、`heal → 承認 → approve`) |
| Qodo | 全 PR を `/agentic_review`。`.pr_agent.toml` に承認ゲート規約 |
| OpenAI | 推論・生成・音声認識(`gpt-4o-transcribe`) |

## 世界観
詠唱者(あなた)/ 詠唱(声)/ 索敵(PC コンテキスト)/ 呪文書(サイトごとの workflow)/ 召喚(TrueForge セッション)/ 契約(承認ゲート)/ 千里眼(Bright Data)/ 発動(貼り付け)

## License
MIT
