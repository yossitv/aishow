# TrueForge ハーネス設定(Step 01)

## 起動
```bash
make harness        # = npx @truefoundry/trueforge@latest → http://localhost:8790(SQLite、認証なし)
```

## 設定手順(UI)
1. **Settings → Models**: OpenAI / `OPENAI_API_KEY` / 既定 gpt-5 系(フォールバック gpt-4.1)→ Create
2. **Settings → Connectors**: Bright Data MCP
   - command `npx`, args `["@brightdata/mcp"]`, env `API_TOKEN=<BRIGHTDATA_API_KEY>`, `GROUPS=code`(最小)
   - 動作確認: チャットで「https://www.example.com を Markdown で取って」→ `scrape_as_markdown` が呼ばれる
3. **Settings → Skills**: `harness/spells/*.md` を登録(GitHub インポート: このリポジトリの `harness/spells`)
4. **Tools**: `paste_to_cursor` と `scraper_approve` を **承認必須** に設定
5. **Save Agent** → 名前 `aishow`

## 記録(Step 01 で埋める)
- Models: (未)
- Connectors: (未)
- Skills: (未)
- 承認必須ツール: (未)
- Bright Data collector id: (未 → CLAUDE.md にも記入)
- API プロトコル(Step 05 が使う): セッション作成 / ターン送信 / イベントストリームのエンドポイントと形式 — https://trueforge.dev を確認して記入
