# カスタムツールのスキーマ(Step 01)

TrueForge が実際にツールを認識できるのは MCP サーバー経由(`api/v1/settings/mcp-servers`、**remote(URL)専用** — 確認済み。`harness/trueforge-api.md` 参照)。
`paste_to_cursor` / `scraper_heal` / `scraper_approve` は Aishow 独自のツールなので、TrueForge に読み込ませるには **自作 MCP サーバーを立てて remote URL として登録する** 必要がある(TrueForge 自身にカスタムツールを直接定義する API は無い — `AgentSpec.mcp_servers[].name` は「設定済み MCP サーバー名」を指すだけで、インラインのツール定義フィールドは SDK 型に存在しない。確認済み)。

## 1. `paste_to_cursor`

Step 05 の CLI が承認イベントを受けて実際に貼り付けを行う想定なので、**ハーネス側では「承認必須のダミーツール」でよい**(実行結果は CLI 側の `tool.response` / 承認 `allow` を待つだけで、TrueForge 側では何もしない no-op ツールとして実装する)。

```json
{
  "name": "paste_to_cursor",
  "description": "承認された本文を、詠唱開始時にフォーカスされていたアプリのカーソル位置へ貼り付ける。承認後に一度だけ呼ばれる不可逆操作。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "text": {
        "type": "string",
        "description": "貼り付ける最終確定テキスト(英文本文)"
      },
      "target": {
        "type": "object",
        "properties": {
          "app": { "type": "string", "description": "貼り付け先アプリ名(例: Google Chrome)" },
          "windowTitle": { "type": "string", "description": "貼り付け先ウィンドウタイトル" }
        },
        "required": ["app", "windowTitle"],
        "additionalProperties": false
      }
    },
    "required": ["text", "target"],
    "additionalProperties": false
  }
}
```

エージェント側設定(`AgentSpec.mcp_servers[]`、確認済みのワイヤ形式):
```json
{ "name": "aishow-tools", "require_approval_for_tools": ["paste_to_cursor"] }
```

## 2. `scraper_heal`

```json
{
  "name": "scraper_heal",
  "description": "会社サイト構造化 collector が壊れたときに、症状を渡して修復案(diff)を生成させる。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "collectorId": { "type": "string", "description": "Bright Data collector id" },
      "symptom": { "type": "string", "description": "症状の説明(例: products が空)" }
    },
    "required": ["collectorId", "symptom"],
    "additionalProperties": false
  }
}
```

## 3. `scraper_approve`

不可逆(collector 定義の恒久変更)なので承認必須。

```json
{
  "name": "scraper_approve",
  "description": "scraper_heal が提案した diff を確定させ、collector に適用する。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "collectorId": { "type": "string", "description": "Bright Data collector id" },
      "responseId": { "type": "string", "description": "承認対象の heal レスポンス id" }
    },
    "required": ["collectorId", "responseId"],
    "additionalProperties": false
  }
}
```

エージェント側設定:
```json
{ "name": "aishow-tools", "require_approval_for_tools": ["scraper_approve"] }
```
(`scraper_heal` は診断だけで副作用がないため承認不要でよい)

## 自作 MCP サーバーの最小構成案(推測・未実装)

TrueForge が話せるのは MCP の Streamable HTTP(remote URL)なので、上記 3 ツールを持つ小さな MCP サーバーを別プロセスで立て、`ngrok` 等でトンネルするか、Step 05 の CLI 自身が `http://localhost:<port>/mcp` を listen して TrueForge から呼ばれるようにする(ローカル同士なら `http://127.0.0.1:<port>/mcp` を `remote` として登録できる可能性が高い — remote = 「stdio ではない HTTP」という意味であり、必ずしもインターネット到達性を要求しないと推測されるが **未検証**)。

- 実装候補: TypeScript/Node の `@modelcontextprotocol/sdk` の `StreamableHTTPServerTransport`、または Python `mcp` SDK
- 最小限は「3 ツールを list_tools で返し、call_tool で `paste_to_cursor`/`scraper_approve` は即座に `{status:"ok"}` を返すだけの no-op」(実処理は Step 05 の Swift CLI 側が承認イベントを見て行う)
- Step 01 の段階ではこのサーバー自体の実装は行わない(発注書は「最小構成案」を書くまでが範囲)。実装は Step 05 以降の判断
