# Aishow(詠唱) — 声で詠唱すると、AI エージェントが現れて仕事をする

Agent Harness Hackathon(2026-08-29, SF)向けプロジェクト要件。**0 から実装**する(VoiceInk / KashinAI はフォークせず、設計だけ参考にする → 参考リポジトリ読解メモは hackathon リポジトリ `ideas/aishow/README.md`)。
**スポンサー製品を使う前提**: TrueForge(ハーネス)/ Bright Data(ライブ Web データ)/ Qodo(PR レビュー)/ OpenAI($50 クレジット)。

---

## 0. 一言で

> **ショートカットキー + 声**。企業サイトの問い合わせフォームを開いたまま `Option+Space` を押し、日本語で「この会社に、うちの音声 SDK の話でコールドメッセージ」と**詠唱**する。
> ローカルの **TrueForge エージェント**が**召喚**され、**いま開いているサイト / サービスを特定**して、対応する **workflow** を走らせる。
> website form なら: **Bright Data MCP でそのサイトの情報(会社概要・製品・最近のニュース)を取得** → OpenAI モデルがユーザーの文体でコールドメッセージを書く → **承認**を経てフォームのカーソル位置に挿入する。

```
shortcut key + voice ─▶ TrueForge agent(local)─▶ 開いているサイト / サービスを特定 ─▶ workflow 分岐
                                                        │
                        ┌───────────────────────────────┼──────────────────────────┐
                        ▼                               ▼                          ▼
                 website form(問い合わせ)          LinkedIn / Slack 等          その他(翻訳)
                 Bright Data MCP でサイト取得      (追加 workflow)
                 → OpenAI がコールドメッセージ
                 → 承認 → フォームに挿入
```
裏側の AI モデルは **OpenAI**(推論・生成・音声認識すべて。ハッカソンの $50 クレジット)。

### 解く課題(提出フォーム Q8)
日本人として米国スタートアップで働いていると、(1) 企業サイトの問い合わせフォームから英語でコールドアウトリーチする作業が、会社を調べる → 英文を書く → 翻訳を直す → 貼る、で毎回 15 分かかる、(2) 相手を調べずに送る「ゴミ DM」は自分の HubSpot にも山ほど届いていて、そうなりたくない、(3) 上司・同僚への英語メッセージも都度 Chrome で翻訳してコピペしている。
→ 「フォームを開いて声で意図を言うだけで、サイトを調べて・文脈を読んで・自分の文体で・確認してから」書いてくれるものが欲しい。

### 世界観(UI 用語)
| 現実 | 世界観 |
|---|---|
| ユーザー | 詠唱者(Caster) |
| 音声入力 | 詠唱(Chant) |
| TrueForge のエージェントセッション | 召喚(Summon)/ 召喚獣 |
| PC コンテキスト収集 | 索敵(Scan) |
| サイト / サービス特定 → workflow 分岐 | 呪文書(Spellbook)— 開いている場所で唱えられる呪文が決まる |
| 個々の workflow(website form / LinkedIn / Slack / 翻訳) | 呪文(Spell) |
| 承認ゲート | 契約(Pact)— 召喚獣は契約なしに現実に触れない |
| Bright Data | 千里眼(Far Sight) |

---

## 1. スコープ

### Must(デモで動く最小)
- M1. ホットキー(push-to-talk)で録音 → 日本語音声をテキスト化
- M2. 詠唱時点の PC コンテキスト取得: 最前面アプリ名・ウィンドウタイトル・(ブラウザなら)URL・ページタイトル・選択テキスト・フォーカス中の入力欄の有無
- M3. **サイト / サービス特定 → workflow 分岐**: URL・アプリ名・ページ構造から `website_form` / `linkedin` / `chat` / `mail` / `general` を判定し、対応する workflow を起動
- M4. **website form workflow**: エージェントが Bright Data MCP で **開いているサイト(会社概要・製品・About・最近のニュース)をライブ取得**し、OpenAI モデルがパーソナライズしたコールドメッセージを生成
- M5. **承認ゲート**: 生成結果を表示し、ユーザーが承認したらフォームのカーソル位置に貼り付け。却下なら何もしない。送信ボタンは押さない
- M5b. TrueForge はローカル(`npx @truefoundry/trueforge`)、モデルは OpenAI(Settings → Models)
- M6. UI に「今なにをしているか / なにを待っているか / なにをしたか」が常時見える(Best UI 軸)
- M7. 開発は PR 経由・Qodo `/agentic_review` を通してマージ(Best Code Quality 軸)

### Should(時間があれば)
- S1. 追加 workflow: LinkedIn → cold DM(人物 pipelines)、Slack/Discord → 軽い英文、Gmail → メール、それ以外 → 翻訳(website_form 以外は M3 の分岐先として追加するだけ)
- S1b. フォームの複数欄(Name / Company / Message)を検出して、Message 以外も埋める提案(承認付き)
- S2. Bright Data のスクレイパー設定(collector id)を `CLAUDE.md` にピン留めし、**欠損検知 → `scraper heal` → 承認 → `approve`** の自己修復ループをエージェント経由で実演
- S3. 「自分の文体」: 過去に書いた英文メッセージ数本を `voice/samples.md` に置き、プロンプトに few-shot で混ぜる
- S4. 二段表示: 詠唱直後に生テキスト(翻訳だけ)を即プレビュー → 調査完了後に本体で差し替え(VoiceInk の二段挿入の思想)

### Won't(今日はやらない)
- ネイティブ macOS アプリ(Swift/SwiftUI)のフル実装、メニューバー常駐 UI
- 常時マイク監視・ウェイクワード
- 送信ボタンの自動クリック(貼り付けまで。送信は人間)
- ベクトル DB・埋め込みによる記憶
- Windows / Linux 対応

---

## 2. アーキテクチャ

```
┌─ macOS(ローカル)──────────────────────────────────────────────┐
│  aishow-cli(Node/TypeScript)                                   │
│   ├ hotkey     : グローバルホットキー(push-to-talk)              │
│   ├ chant      : マイク録音(sox/ffmpeg)→ OpenAI STT → 日本語text │
│   ├ scan       : osascript/lsappinfo で最前面アプリ・タイトル・URL・選択text │
│   ├ detect     : URL/アプリ/ページ構造 → site/service 特定 → workflow 選択 │
│   ├ summon     : TrueForge SDK でセッション作成・ターン送信・イベント購読 │
│   ├ pact       : 承認 UI(ターミナル TUI or ローカル Web UI)           │
│   └ cast       : クリップボード保存 → 貼付け(Cmd+V)→ 復元          │
└───────────────┬─────────────────────────────────────────────────┘
                │ HTTP / SSE(@truefoundry/trueforge-sdk)
┌───────────────▼─────────────────────────────────────────────────┐
│  TrueForge(npx @truefoundry/trueforge, localhost:8790)          │
│   ├ Model      : OpenAI(gpt-5 系 / gpt-4.1、$50 クレジット)— 唯一のモデル │
│   ├ Skills     : workflow ごとの呪文(website_form / linkedin / chat / translate)│
│   ├ Connectors : Bright Data MCP(scrape_as_markdown / search_engine / discover)│
│   ├ Approval   : 「paste_to_cursor」「scraper_approve」は承認必須ツール │
│   ├ Sandbox    : (任意)Daytona で `bdata scraper heal` を隔離実行  │
│   ├ Sub-agents : サイト調査(About / 製品 / ニュース)を並列委任        │
│   └ Session    : SQLite 永続。同じ相手への再詠唱は履歴を引き継ぐ      │
└───────────────┬─────────────────────────────────────────────────┘
                │ MCP
┌───────────────▼─────────────────────────────────────────────────┐
│  Bright Data                                                    │
│   ├ MCP(@brightdata/mcp, GROUPS=code など)                       │
│   ├ CLI(bdata scraper run / heal / approve)                      │
│   └ Scraper Studio collector(会社サイト About/製品 抽出。id を CLAUDE.md にピン留め)│
└─────────────────────────────────────────────────────────────────┘
       GitHub PR ──▶ Qodo Merge(/agentic_describe, /agentic_review) ──▶ merge
```

### なぜこの構成か
- **ネイティブアプリを書かない**: 参考2リポジトリの知見から、macOS の「最前面アプリ・URL・選択テキスト・貼り付け」は `osascript` + `lsappinfo` + クリップボードで全部取れる(KashinAI が実証)。1日で 0 から作るなら Node CLI + osascript が最速
- **音声認識はクラウド STT**: whisper.cpp や SpeechAnalyzer の組み込みは今日は割に合わない。録音 → OpenAI `gpt-4o-transcribe`(日本語対応)で十分。OpenAI クレジットの使い道にもなる
- **workflow 分岐はローカル、実行はハーネス**: 「どのサイト/サービスか」の特定は CLI 側でルールベースに即決(速い・テスト可能)。特定した workflow 名とコンテキストを TrueForge に渡し、調査(サブエージェント並列)・ツール接続(Bright Data MCP)・生成・承認ゲート・セッション永続はすべてハーネス側。CLI は入出力と分岐だけ → 「薄いラッパーではない」と言える
- **モデルは OpenAI 一本**: TrueForge の Settings → Models に OpenAI を登録。推論・生成・STT(`gpt-4o-transcribe`)を同一ベンダーで揃え、クレジットを集中させる
- **不可逆操作を明確化**: このアプリで不可逆なのは「他アプリへの貼り付け」と「スクレイパーの approve」。両方を承認必須ツールにすることで Best UI 軸と Bright Data 軸を同時に満たす

---

## 3. 機能要件

### F1. 詠唱(Chant)— 音声入力
- F1.1 グローバルホットキー(既定 `Option+Space`、押している間録音 = push-to-talk。トグル方式も設定で選択可)
- F1.2 録音: 16kHz mono WAV。`sox -d` または `ffmpeg -f avfoundation`。最大 30 秒で自動停止
- F1.3 STT: OpenAI Audio Transcriptions(`gpt-4o-transcribe`、`language: ja`)。失敗時は `whisper-1` にフォールバック
- F1.4 無音・1 秒未満は破棄して「詠唱が短すぎる」と表示
- F1.5 ホットキーを押した**瞬間**に F2 の索敵を開始(自分の UI を出す前に最前面アプリを取る。KashinAI の教訓)

### F2. 索敵(Scan)— PC コンテキスト収集
- F2.1 最前面アプリ: `lsappinfo front` + `osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'` の両方を取って突き合わせ
- F2.2 ウィンドウタイトル: System Events の `name of front window`
- F2.3 ブラウザ URL・タイトル: Chrome/Arc/Brave/Edge は `tell application "Google Chrome" to get URL of active tab of front window`、Safari は同等。取れなければ `Cmd+L → Cmd+C` のキーボードフォールバック
- F2.4 選択テキスト: クリップボード退避 → 空 → `Cmd+C` 送信 → 150ms 待ち → 読み取り → 復元
- F2.5 コンテキストパック(JSON):
  ```json
  {
    "app": "Google Chrome", "windowTitle": "...", "url": "https://www.linkedin.com/in/xxx/",
    "selectedText": "...", "focusedInput": true,
    "site": {"domain": "acme.com", "kind": "website_form|linkedin|chat|mail|general", "workflow": "website_form"},
    "capturedAt": "2026-08-29T15:30:00-07:00", "chant": "この人にコールドメッセージ、うちの音声 SDK の話で"
  }
  ```
- F2.6 **サイト / サービス特定 → workflow 選択**はルールベース(正規表現 + ページ構造)。判定表(上から順に評価、最初に当たったもの):
  | 条件 | site.kind | workflow(呪文) |
  |---|---|---|
  | URL が `linkedin.com/in/` or `linkedin.com/messaging/` | linkedin | `linkedin_dm`(S1) |
  | アプリが Slack / Discord / Teams / Messages | chat | `casual_en`(S1) |
  | アプリが Mail / URL が `mail.google.com` | mail | `email_en`(S1) |
  | **ブラウザ、かつ URL パスに `contact|inquiry|get-in-touch|demo|sales|support` を含む、または ページに `<form>` と `<textarea>` がある**(AppleScript で `document.querySelector('form textarea')` を JS 実行) | **website_form** | **`website_form`(M4)** |
  | ブラウザ、それ以外 | browser | `translate` |
  | その他 | general | `translate` |
- F2.6b `site.domain` は URL の登録ドメイン(`www.` を除く)。Bright Data に渡す調査対象のルートになる
- F2.7 権限: Accessibility と Automation(Apple Events)。初回に不足を検知して System Settings への導線を表示

### F3. 召喚(Summon)— TrueForge エージェント
- F3.1 起動時に TrueForge(`localhost:8790`)に接続。未起動なら `npx @truefoundry/trueforge@latest` の起動方法を表示
- F3.1b モデル: OpenAI のみ(Settings → Models で登録。既定 `gpt-5` 系、フォールバック `gpt-4.1`)
- F3.2 セッション: `site.domain` ごとに 1 セッション。同じ会社への再詠唱は履歴を継続(セッション永続の実演)
- F3.3 ターン送信: workflow 名で呪文(Skill / system prompt)を選び、コンテキストパック + 詠唱テキストを渡す
- F3.4 エージェントに与えるツール:
  - Bright Data MCP: `scrape_as_markdown`(`https://{domain}/`, `/about`, `/products`, `/blog|/news`)、`search_engine`(`"{domain}" news 2026`)、`discover`
  - `paste_to_cursor(text)`: **承認必須**。CLI 側が実行(ローカルツール or CLI が結果を受けて実行)
  - `scraper_heal(collectorId, symptom)` / `scraper_approve(collectorId)`: 後者は**承認必須**(S2)
- F3.5 呪文書(prompt)の共通ルール:
  - 出力言語は英語(translate のみ指示に従う)。ユーザーは日本語で話す
  - website_form: Bright Data で取得したサイト情報から **具体的な事実を最低 1 つ引用**(製品名・直近の発表・採用中の職種・ミッション文)。引用できなければ「調査不足」と正直に言って送らせない。フォームの文脈(Contact Sales / Partnership / Support)に合わせて件名的な 1 行目を変える
  - 文体: `voice/samples.md` の例文に合わせる(S3)。絵文字なし、150 語以内
  - 不可逆ツール(`paste_to_cursor`)は最終出力が確定した後に 1 回だけ呼ぶ
- F3.6 サブエージェント: website_form では「会社概要(About)」「製品・価格」「最近のニュース」を並列委任し、親が統合(ハーネスの機能実演)
- F3.7 イベント購読: tool_call 開始/終了、承認待ち、最終回答を SSE で受け UI に流す

### F4. 契約(Pact)— 承認ゲート & UI
- F4.1 UI はターミナル TUI(Ink)またはローカル Web UI(`@truefoundry/trueforge-ui` 埋め込み)。**どちらか 1 つ**、迷ったら TrueForge 同梱 UI を使い CLI はサイドカーにする
- F4.2 常時 3 行が見える: 「いま: acme.com/about を取得中」「待ち: なし / あなたの承認」「済み: website_form と特定 ✔、製品ページ取得 ✔」
- F4.3 承認ダイアログ: 特定した workflow 名(「website_form @ acme.com」)+ 生成メッセージ全文 + 引用した根拠(URL)+ 貼り付け先(アプリ名・ウィンドウタイトル・入力欄)を表示。`承認 / 編集して承認 / 却下`
- F4.4 承認前に最前面アプリが変わっていたら警告(貼り付け先ズレ防止)
- F4.5 却下は理由を 1 行入力でき、それを同セッションに返して再生成

### F5. 発動(Cast)— 貼り付け
- F5.1 クリップボード退避 → テキスト書込 → 対象アプリを `activate` → `Cmd+V` keystroke → 300ms 後にクリップボード復元
- F5.2 貼り付けのみ。**送信(Enter)はしない**
- F5.3 実行ログ(誰に・何を・いつ・根拠 URL)を `~/.aishow/log.jsonl` に追記

### F6. 千里眼(Far Sight)— Bright Data
- F6.1 MCP を TrueForge Connectors に登録(`API_TOKEN`、`GROUPS` は必要最小)
- F6.2 website_form workflow 用に「任意ドメインの About / 製品ページから `companyName, tagline, products[], latestNews`」を抽出する Scraper Studio collector を 1 つ作り、id を `CLAUDE.md` の「Bright Data scrapers(再利用。作り直さないこと)」節にピン留め(Git 管理)。MCP の `scrape_as_markdown` は生 Markdown、collector は構造化、の二段構え
- F6.3 (S2)取得結果のスキーマ検証(`companyName`, `tagline`, `products[]` 必須)。欠損 → エージェントが `scraper heal` → diff を承認ゲートに載せる → `approve`
- F6.4 禁止事項の遵守: ログイン必須・有料壁は取らない(企業の公開サイトのみ)。LinkedIn(S1)は Bright Data の公開データ pipelines 経由のみ。個人データはセッション外に永続化しない(ログには URL とメッセージのみ)

### F7. 品質(Qodo)
- F7.1 リポジトリルートに `.pr_agent.toml`(`/agentic_describe`, `/agentic_review`、`inline_comments_severity_threshold = 3`、ガイドライン「不可逆操作の前に承認ゲート」「API キー直書き禁止」)
- F7.2 機能ごとに PR(最低 3 本: scan/chant、summon/pact、brightdata)。High 指摘は全件対応してからマージ
- F7.3 README に Qodo の指摘と修正の実例を 1〜2 件リンク(提出 Q10 用)

---

## 4. 非機能要件
- N1. 詠唱終了 → 承認ダイアログ表示まで、translate / casual_en は **5 秒以内**、website_form(Bright Data 調査あり)は **30 秒以内**。超過時は「調査中…」を UI に出し続ける
- N2. API キーは環境変数 / `.env`(gitignore)。リポジトリに露出しない
- N3. すべての外部呼び出し(STT / TrueForge / Bright Data)が失敗しても、CLI は落ちずにエラーを UI に表示し、クリップボードは必ず復元する
- N4. macOS 14+、Node 22.14+(TrueForge 要件)
- N5. ライセンス: MIT。リポジトリ public(ハッカソン規約)

---

## 5. リポジトリ構成(案)
```
aishow/
├ README.md                 # 何を・アーキテクチャ・起動手順・Qodo 実例リンク
├ CLAUDE.md                 # Bright Data collector id ピン留め、開発規約
├ .pr_agent.toml
├ .env.example              # OPENAI_API_KEY, BRIGHTDATA_API_KEY, TRUEFORGE_URL
├ package.json              # pnpm、node --test
├ src/
│  ├ cli.ts                 # エントリ。hotkey → chant → scan → summon → pact → cast
│  ├ chant/  record.ts stt.ts
│  ├ scan/   frontmost.ts browser.ts selection.ts
│  ├ detect/ site.ts workflows.ts        # サイト/サービス特定 → workflow 選択。純粋関数(テスト対象)
│  ├ summon/ trueforge.ts spells/{website_form,linkedin_dm,casual_en,email_en,translate}.md
│  ├ pact/   ui.ts approval.ts
│  ├ cast/   paste.ts clipboard.ts
│  └ farsight/ brightdata.ts schema.ts heal.ts
├ scripts/  osa/*.applescript, setup-permissions.md
├ voice/samples.md          # 自分の英文サンプル(few-shot)
└ tests/ unit/classify.test.ts fixtures/context/*.json
```

---

## 6. デモシナリオ(3 分動画・提出 Q7)
1. **[0:00–0:20] About**: 課題(ゴミ DM、翻訳コピペ)と「詠唱→召喚→契約→発動」の一枚絵
2. **[0:20–0:50] Tech**: 上のアーキテクチャ図。TrueForge が「調査・ツール・承認・セッション」を担当、CLI は入出力だけ、と明言
3. **[0:50–2:20] Demo**:
   - Chrome で企業サイトの Contact フォーム(例: `acme.com/contact`)を開き、Message 欄にカーソル → `Option+Space` 押しながら日本語で「この会社に、うちの音声 SDK の話でコールドメッセージ」
   - UI: 索敵 ✔ → **「website_form @ acme.com」を特定** → 召喚 → 「About / 製品 / ニュース」の調査が並列で走る(Bright Data の tool_call が見える)→ OpenAI が生成
   - 承認ダイアログ: workflow 名 + 本文 + 引用根拠 URL + 貼り付け先。「編集して承認」で 1 語直す → フォームの Message 欄に挿入される(送信はしない)
   - 続けて Slack に切替 → 「明日のミーティング 10 分遅れるって軽く」→ 5 秒で英文がプレビュー → 承認 → 挿入
   - (S2 があれば)会社サイトが取れなくなったケース → エージェントが `scraper heal` を提案 → diff を承認 → 復旧
4. **[2:20–3:00] Learning**: 詰まった点(権限、承認ゲート設定、Bright Data のレート等)を正直に

---

## 7. タイムボックス(現在 15:22 PDT、締切 18:00)
残り約 2.5 時間。**Must だけ**を狙い、Should は S1(判定表は F2.6 に既にある。実装 15 分)のみ。
| 時刻 | やること | 完了条件 |
|---|---|---|
| 15:25–15:45 | リポジトリ作成(public, MIT)、`npx @truefoundry/trueforge` 起動、**OpenAI モデル登録**、Bright Data MCP を Connectors に追加、`.pr_agent.toml`、Qodo App インストール | TrueForge のチャット UI から Bright Data で任意の企業サイトが Markdown で取れる |
| 15:45–16:20 | `scan/`(osascript)+ `detect/`(サイト特定 → workflow)+ `cast/`(貼り付け)+ テスト | Contact ページを開いた状態で `website_form @ domain` と判定され、任意テキストがフォームに貼れる。**PR #1 → Qodo** |
| 16:20–16:50 | `chant/`(録音 + STT) | 日本語で話した内容がテキストになる。**PR #2** |
| 16:50–17:25 | `summon/` + website_form の呪文 + 承認フロー(まずは TrueForge 同梱 UI の承認ゲートを使い、CLI は結果を受けて貼り付け) | Contact フォーム → 詠唱 → Bright Data 調査 → 承認 → 挿入が通る。**PR #3** |
| 17:25–17:45 | デモ録画(3 分)、README、CLAUDE.md に collector / 使い方 | 動画 URL 取得 |
| 17:45–18:00 | 提出フォーム(Q8–Q19)、LinkedIn 投稿(任意) | 送信 |

**退避策**
- STT が間に合わない → ホットキー後にテキスト入力で詠唱(「詠唱はキーボードでも可」と割り切る)。他は全部同じ
- TrueForge SDK のストリーミングで詰まる → TrueForge 同梱チャット UI をそのまま使い、CLI は「コンテキストパックをクリップボードに作る」+「承認後の貼り付け」だけを担う。ハーネス使用の実態は変わらない
- `<form textarea>` 検出(AppleScript JS 実行)が動かない → URL パスのキーワードだけで website_form 判定。それも外れたら「詠唱の先頭で『フォーム』と言えば website_form」の音声オーバーライド
- Bright Data の `scrape_as_markdown` がブロックされる → `search_engine` で `"{domain}"` の検索結果スニペットだけで書く。それも無理なら選択テキスト(ページ本文をドラッグ選択)で代替

---

## 8. 提出フォームへの対応(Q9–Q11 の素材)
- **Q9 TrueForge**: ローカル起動のハーネス上で OpenAI モデルを動かし、workflow ごとの Skill(呪文)、Bright Data MCP 接続、`paste_to_cursor` と `scraper_approve` の承認必須ツール化、About/製品/ニュース調査のサブエージェント並列、ドメインごとのセッション永続。CLI は「入出力 + サイト特定 → workflow 分岐」のみで、調査・生成・承認・行動は全部ハーネス
- **Q10 Qodo**: 3 PR を `/agentic_review`。ガイドラインに「不可逆操作前の承認」「キー直書き禁止」を書き、実際の指摘 → 修正を README にリンク
- **Q11 Bright Data**: website_form workflow の中核。開いているサイトのドメインをそのまま MCP に渡してライブ取得(調査がなければ送らせない設計)。汎用「会社サイト構造化」collector の id を `CLAUDE.md` にピン留めして Git 管理。欠損検知 → `heal` → 承認 → `approve` を(実装できた範囲で)実演

---

## 9. 参考リポジトリから持ち込む設計(コードは持ち込まない)
- **VoiceInk-japanese**: push-to-talk の設計、クリップボード退避/復元、**二段挿入**(即時プレビュー → 完成後差し替え)の思想、書記素クラスタ単位の置換(将来のネイティブ化時)
- **KashinAI**: `osascript` + `lsappinfo` による最前面アプリ取得、**自分の UI を出す前に索敵する**、ブラウザ URL の多段フォールバック、クリップボード経由の選択テキスト取得、`contextKind` ルールベース判定 + 文体はプロンプトに委ねる、フィクスチャドリブンテスト
- 詳細: hackathon リポジトリ `ideas/aishow/README.md`

---

## 10. 将来(ハッカソン後)
- Swift/SwiftUI でメニューバー常駐アプリ化(Accessibility API 直叩き、SpeechAnalyzer でオンデバイス STT、Foundation Models でオフライン翻訳)
- 呪文書のユーザー定義(アプリ/URL パターン → プロンプト)
- HubSpot / Gmail への送信を承認ゲート付きで追加(「貼り付けまで」から「送信まで」へ)
- 文体学習: 自分が実際に送ったメッセージを蓄積して few-shot を自動更新
