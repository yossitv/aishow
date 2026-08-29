# TrueForge ハーネス設定(Step 01)

## 起動
```bash
make harness        # = npx @truefoundry/trueforge@latest → http://localhost:8790(SQLite、認証なし)
```
実機確認済み: 起動後ログに `Agent server listening on http://localhost:8790 (docs at /api/v1/docs)`。`GET /api/v1/openapi.json` で実際のスキーマが取れる。`GET /api/v1/auth/me` は未認証でも `{"type":"default","role":"admin"}` を返す(ローカルは認証なし)。

## 設定手順

**訂正**: 発注書・旧版の本節にあった「Connectors に `command: npx, args: ["@brightdata/mcp"]`」は**実機検証の結果できないことを確認**した(下記参照)。Bright Data はホスト版の remote URL を使う。

1. **Settings → Models**: OpenAI / `OPENAI_API_KEY` / 既定 gpt-5 系(フォールバック gpt-4.1)→ Create
   - API から同等の設定は確認済み(下記「記録」参照)。UI でも同じ内容を入力すればよい
2. **Settings → Connectors**: Bright Data MCP
   - **remote URL** として登録: `https://mcp.brightdata.com/mcp?token=<BRIGHTDATA_API_KEY>&groups=<GROUPS>`(Bright Data 公式のホスト型 MCP エンドポイント。streamable-HTTP)
   - `GROUPS` は用途別のツールバンドル ID(`ecommerce` / `social` / `browser` / `business` / `finance` / `research` / `app_stores` / `travel` / `geo` / `code` / `advanced_scraping`)。**website_form 呪文は base tools(`search_engine`, `scrape_as_markdown`, `discover` — GROUPS 無指定でも常に有効)だけで足りる**ので、最小構成は **`GROUPS` を付けない**(空文字/省略)ことを推奨。会社サイト構造化の追加調査に GitHub 情報が要るなら `code` を足す
   - 動作確認: チャットで「https://www.example.com を Markdown で取って」→ `scrape_as_markdown` が呼ばれる(**未検証** — API トークンを URL に載せて外部の Bright Data ホストへ実際に接続する検証は今回のセッションでは見送った。安全側に倒し、ローカルの `npx @brightdata/mcp`(stdio)は数秒起動して落ちないことのみ確認した)
3. **Settings → Skills**: `harness/spells/*.md` を登録(GitHub インポート: このリポジトリの `harness/spells`)。`website_form.md` に `name`/`description` フロントマターを追加済み(**TrueForge が要求する追加フィールドの有無は未確認**)
4. **Tools**: `paste_to_cursor` と `scraper_approve` を **承認必須** に設定
   - 実際の設定場所は Settings ではなく **Agent の manifest の `mcp_servers[].require_approval_for_tools`**(確認済み。下記参照)。これらのツールは TrueForge に組み込みで存在するのではなく、自作 MCP サーバーとして提供する必要がある(`harness/tools.md` の「自作 MCP サーバーの最小構成案」参照。未実装)
5. **Save Agent** → 名前 `aishow`(API で作成すると `name` はイミュータブル。確認済み)

## 記録(Step 01 で埋めた内容)

- **Models**: OpenAI provider を API 経由で作成・確認済み。
  ```
  POST /api/v1/settings/model-providers
  { "manifest": { "type": "openai", "auth": { "api_key": "<OPENAI_API_KEY>" },
      "models": [ {"name":"gpt-5.2","model_id":"gpt-5.2","properties":{}},
                  {"name":"gpt-4.1","model_id":"gpt-4.1","properties":{}} ] } }
  ```
  → 200 で `openai` プロバイダが登録され、一覧取得時は `auth` の値がリダクトされることを確認。**キーの値自体はこのファイル・コミットに書いていない**(`aishow/.env` から都度読む運用)
- **Connectors**: Bright Data のホスト型 remote MCP URL(`https://mcp.brightdata.com/mcp?token=...&groups=...`)での登録手順を上記に記録。**実登録・動作確認は未実施**(トークンを含む URL を外部ホストへ送る実験を安全のため見送った)。ローカル `npx @brightdata/mcp`(stdio)は起動自体は確認済みだが、TrueForge には**そのままでは繋がらない**(remote URL 専用のため。詳細は `harness/trueforge-api.md`)
- **Skills**: `harness/spells/website_form.md` に `name: website_form` / `description` のフロントマターを付与。他の呪文(casual_en / email_en / linkedin_dm / translate)は骨のまま(発注書どおり)。実際の GitHub インポート操作は UI 前提のため未実施
- **承認必須ツール**: API で確認済み。Agent 更新時に以下を渡すと `require_approval_for_tools` がそのまま反映される:
  ```
  PUT /api/v1/agents/{agent_id}
  { "manifest": { ..., "mcp_servers": [
      { "name": "aishow-tools", "require_approval_for_tools": ["paste_to_cursor", "scraper_approve"] }
  ] } }
  ```
  ただし `aishow-tools` という MCP サーバー自体(`paste_to_cursor` / `scraper_heal` / `scraper_approve` を提供する)はまだ存在しない。`harness/tools.md` の最小構成案を Step 05 以降で実装する必要がある
- **Bright Data collector id**: **未作成**。汎用「会社サイト構造化」collector(companyName / tagline / products[] / latestNews)を作るには Bright Data の管理画面(または `bdata` CLI)でのアカウント操作が要り、今回のセッションでは実施しなかった。`CLAUDE.md` の該当節はプレースホルダのまま(要 Step 01 の追加作業、または次エージェントへの持ち越し)
- **API プロトコル(Step 05 が使う)**: `harness/trueforge-api.md` に全文を記録(セッション作成 / ターン送信 / SSE イベント種別 / 承認の返し方 / エラー形。実機 curl で検証済み)

## 実機で作った一時リソース(このセッションのみ・後始末済み)
- ローカル TrueForge プロセスは検証後に停止済み(`kill`)。作業用 SQLite は `/private/tmp/...scratchpad/trueforge.sqlite` に残っているのみでリポジトリには含まれない
- 作成した OpenAI provider / `aishow` agent / セッション / ダミー MCP server(`dummy-remote`)はそのプロセスと共に消えている(SQLite ファイル自体はスクラッチパッドに残るが未使用)
