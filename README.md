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

## 使い方(開発中)
```bash
cp .env.example .env            # OPENAI_API_KEY, BRIGHTDATA_API_KEY を入れる
make harness                    # 別ターミナルで TrueForge を起動(http://localhost:8790)→ harness/SETUP.md
swift build && swift test
.build/debug/aishow scan --json # 索敵
.build/debug/aishow summon      # 詠唱 → 召喚 → 承認 → 発動
make app && open dist/Aishow.app  # メニューバー常駐
```

## ドキュメント
- [docs/idea.md](docs/idea.md) — 要件
- [docs/steps/](docs/steps/README.md) — 実装 Step(発注書)。1 Step = 1 PR = Qodo レビュー
- [docs/kanban.xlsx](docs/kanban.xlsx) — 進捗(`python3 scripts/kanban.py`)
- [harness/SETUP.md](harness/SETUP.md) — TrueForge / OpenAI / Bright Data の設定
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
