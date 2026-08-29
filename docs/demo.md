# デモ撮影台本(3 分・提出 Q7)

## 事前準備(撮影前)
```bash
make harness                          # ターミナル A: TrueForge
./scripts/register-brightdata.sh      # ターミナル B: Bright Data コネクタ登録(1 回)
make app && open dist/Aishow.app      # メニューバーに杖アイコン
```
- 初回: マイク / Accessibility / Automation を許可(メニューバー →「状態…」に導線)
- Chrome で実在する企業の Contact ページを開き、Message 欄にカーソルを置く(例: 音声 SDK を売り込みたい先)
- 画面収録: QuickTime(⌘⇧5)。メニューバーの Popover が入る範囲を選択

## 台本
| 時刻 | 画面 | ナレーション(英語) |
|---|---|---|
| 0:00–0:20 | README のタイトル + 一枚絵 | "Aishow — 'chant' in Japanese. I'm a Japanese engineer at a US startup. Cold outreach in English used to take me 15 minutes: research the company, write, fix the translation, paste. And my own inbox is full of lazy DMs that never looked at who I am." |
| 0:20–0:50 | アーキテクチャ図(README) | "The Swift menu-bar app is only ears, eyes and hands. TrueForge is the brain: OpenAI model, Bright Data MCP, per-domain sessions. The app detects which site you're on, routes to a workflow, and gates the only irreversible action — pasting — behind human approval." |
| 0:50–2:20 | 実演 | 1) Contact ページ → Option+Space 押しながら日本語で「この会社に、うちの音声 SDK の話でコールドメッセージ」 2) Popover: 索敵 ✔ → `website_form @ <domain>` → 召喚 → 「いま: scrape_as_markdown …」 3) 承認ポップオーバー: 根拠 URL・本文。1 語直して「承認」 4) Message 欄に英文が入る。**送信しない** 5) Slack に切替 → 「明日 10 分遅れるって軽く」→ 数秒で英文 → 承認 → 挿入 |
| 2:20–3:00 | ターミナル / PR 一覧 | "Every step was a PR reviewed by Qodo. What broke: TrueForge MCP connectors are remote-only, so we moved the approval gate into the app; the wire protocol is snake_case and errors arrive inside turn.done with HTTP 200. Bright Data scraper config lives in CLAUDE.md so healing goes through the same approval path." |

## 失敗時の退避
- 音声が拾えない → `.build/debug/aishow summon --chant "…"` を CLI で見せる(承認は y/e/n)
- Bright Data が遅い → `--dry-run` で提案表示まで
- TrueForge 落ちた → `make harness` 再起動。セッションは SQLite に残る
