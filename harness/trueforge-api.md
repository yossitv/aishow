# TrueForge HTTP API プロトコル(Step 05 実装用)

Step 05 の `Sources/aishow/Summon/TrueForgeClient.swift` はこのファイルだけを見て書けるようにする。**確認済み**は実際にローカル起動して curl で叩いた結果、または `@truefoundry/trueforge-sdk@0.1.3`(npm)の生成コード(`dist/cjs/**/Client.js`)と同梱 `reference.md` から直接読んだ実装。**推測**は明示する。

## 検証方法(再現手順)

```bash
PORT=8790 SQLITE_PATH=/path/to/scratch/trueforge.sqlite npx -y @truefoundry/trueforge@latest
```
起動ログに `Agent server listening on http://localhost:8790 (docs at /api/v1/docs)` と出るまで数秒〜数十秒。`GET /api/v1/openapi.json` で実際の OpenAPI スキーマが取れる(今回 SDK の TS 型と完全一致することを確認済み)。

## ベース URL / 認証(確認済み)

- 既定 `http://localhost:8790`。ローカル(standalone)モードは **認証なし**(起動ログに `warn Auth is disabled; browser login is off`)
- `GET /api/v1/auth/me` → `{"type":"default","email":"trueforge-default","role":"admin"}`(未認証でも 200)
- SDK はリクエストごとに `Authorization: Bearer <token>` を付与できる仕組みを持つが、ローカルでは不要。Step 05 の Swift クライアントは `TRUEFORGE_URL` のみで動かしてよく、認証ヘッダは付けない(将来トークンが要る場合に備え `Authorization` ヘッダ注入口だけ用意しておくと安全)
- SQLite に永続化。プロセス再起動後もセッションは残る

## 全体の流れ(確認済み)

1. **エージェント作成**(`aishow` を 1 回だけ Saved Agent として作成。Step 01 で実施)
2. **セッション作成**: `agent: { name: "aishow" }` を渡すと、その後のターンで常に最新のエージェント設定を解決する(named/reference セッション)
3. **ターン(メッセージ)送信**: セッションに対して `input` 配列(ユーザーメッセージ or 承認/ツール応答の再開アイテム)を POST。`stream: true`(既定)で SSE が返る
4. **イベントストリームを読む**: `tool_call` の開始・完了、`tool.approval_required`(承認要求)、`turn.done`(完了)などを拾う
5. **承認を返す**: 別ターンとして `user.tool_approval` を `input` に入れて POST(セッションは同じ、`previous_turn_id` は自動で直前のターンに続く)

## エンドポイント一覧(確認済み。すべて `curl` で実行して疎通確認済み)

ベースパスは `api/v1/`。

### エージェント

| メソッド | パス | 用途 |
|---|---|---|
| GET | `/api/v1/agents` | 一覧 |
| POST | `/api/v1/agents` | 作成(`{ name, manifest: AgentSpec }`)。**`name` は一度決めたら変更不可** |
| GET | `/api/v1/agents/{agent_id}` | 取得(id はイミュータブル、name とは別) |
| PUT | `/api/v1/agents/{agent_id}` | 更新(manifest 全体を置き換え) |
| DELETE | `/api/v1/agents/{agent_id}` | 削除 |

`AgentSpec`(ワイヤ形式は snake_case。SDK の TS 型は camelCase だが JSON on the wire は snake_case ── 実機で確認済み):
```json
{
  "model": { "name": "openai/gpt-5.2", "params": { "temperature": 0.7 } },
  "instructions": "system prompt...",
  "mcp_servers": [
    {
      "name": "brightdata",
      "enable_tools": ["@all"],
      "require_approval_for_tools": ["@write", "@destructive"],
      "preload": false
    }
  ],
  "skills": [{ "name": "website_form" }],
  "config": {
    "iteration_limit": 100,
    "sandbox": { "enabled": false, "file_downloads": true }
  }
}
```
- `mcp_servers[].require_approval_for_tools` は `@all` / `@write` / `@destructive` または個別ツール名のリスト。**MCP ツールの承認要否はここで宣言する**(呪文側からは変えられない)
- `skills` を使うには `config.sandbox.enabled: true` が必須(確認済みのエラーではないが SDK 型コメントに明記。未検証)

### セッション

| メソッド | パス | 用途 |
|---|---|---|
| GET | `/api/v1/sessions` | 一覧(`created_by` でスコープ、`agent_id` でフィルタ可) |
| POST | `/api/v1/sessions` | 作成 |
| GET | `/api/v1/sessions/{session_id}` | 取得 |
| PATCH | `/api/v1/sessions/{session_id}` | 更新(inline agent の spec 差し替えのみ。named セッションは拒否) |
| DELETE | `/api/v1/sessions/{session_id}` | 削除(ターン・イベントも消える) |
| POST | `/api/v1/sessions/{session_id}/cancel` | 実行中の最後のターンをキャンセル |

作成リクエスト(確認済み。実際に叩いて `session.id` を取得):
```bash
curl -s -X POST http://localhost:8790/api/v1/sessions \
  -H "Content-Type: application/json" \
  -d '{"agent":{"name":"aishow"}}'
```
```json
{"data":{"id":"01m17vjsterg0gz52djnq2wk3c","agent":{"type":"reference","id":"...","name":"aishow"},"title":null,"created_by":"trueforge-default","created_at":"...","updated_at":"..."}}
```
- **セッションキーは `id`(ULID 文字列)**。Step 05 の `~/.aishow/sessions.json` は `domain → sessionId(=id)` のマッピングでよい
- 同じドメインへの 2 回目は、保存しておいた `session_id` に対して `POST /turns` するだけで継続(履歴はサーバー側が保持。クライアントは会話全文を送り直さなくてよい)

### ターン(メッセージ送信・確認済み)

`POST /api/v1/sessions/{session_id}/turns`

リクエスト body:
```json
{
  "input": [
    { "type": "user.message", "content": "Say hello in one short sentence." }
  ],
  "previous_turn_id": "auto"
}
```
- `previous_turn_id` は省略可(既定 `auto` = セッションの最後のターンに自動チェーン)。新規ルートにしたい場合のみ `"none"`
- `stream`(既定 true)を省略すると **SSE** が返る。`false` にすると `state.status: "running"` の Turn オブジェクトが即座に返り、バックグラウンドで実行が進む(その場合は `GET /turns/{turn_id}` かサブスクライブで完了を見る)
- **Aishow の `workflow` 名 + `ContextPack` JSON + 詠唱テキストは、`content` に文字列として埋め込む**(TrueForge の `user.message.content` はプレーン文字列 or 構造化パーツのみで、専用のメタデータフィールドは存在しない・確認済み)。推奨フォーマット(推測。Skill 側の `_common.md` が読める形なら JSON で先頭に付与):
  ```
  workflow: website_form
  context: {"app":"Google Chrome","windowTitle":"Contact Us – Acme","url":"https://acme.com/contact","pageTitle":"Contact","selectedText":null,"focusedInput":true,"hasFormTextarea":true}
  chant: この会社に音声SDKの話でコールドメッセージ
  ```

curl 例(SSE をそのまま出力・確認済み):
```bash
SID=<session_id から>
curl -s -N -X POST "http://localhost:8790/api/v1/sessions/$SID/turns" \
  -H "Content-Type: application/json" -H "Accept: text/event-stream" \
  -d '{"input":[{"type":"user.message","content":"..."}]}'
```

### イベントストリーム(SSE。確認済み)

形式: `text/event-stream`、各イベントは
```
data: {"type":"...", ...}
id: <連番>

```
実機で観測したイベント種別(順番はこの通り):
```
data: {"type":"turn.created","id":"...","turn_id":"...","previous_turn_id":null,"input":[...],"state":{"status":"running"},"created_at":"...","thread_id":null}
data: {"type":"model.message","thread_id":"main","created_at":"...","id":"..."}
data: {"type":"turn.done","id":"...","created_at":"...","state":{"status":"error"|"done"|"cancelled", "message"?:string, "completed_at":"...","metrics":{...}},"thread_id":null}
```
SDK 型定義(`TurnStreamingEvent` union)から確認できる **全イベント種別**:

| type | いつ | 主なフィールド |
|---|---|---|
| `turn.created` | ターン開始直後 | `turn_id`, `previous_turn_id`, `state.status="running"` |
| `thread.created` | サブエージェント(thread)開始時。ルートは `thread_id: "main"` | `thread_id`, `agent_info`, `parent`, `title` |
| `mcp.initialize` | MCP サーバー接続完了 | `mcp_servers[]`(名前・状態) |
| `mcp.auth_required` | MCP サーバーが OAuth 等の認可待ち | `mcp_servers[].auth_url` |
| `sandbox.created` | サンドボックス起動時(skills 使用時など) | `sandbox_id` |
| `model.message.delta` | ストリーミングの差分(**逐次表示に使うのはこれ**) | `content`(差分テキスト), `tool_calls[]`(部分), `reasoning_content` |
| `model.message` | 1 回分のモデル応答が確定 | `content`, `tool_calls: ToolCall[]`, `finish_reason`, `usage` |
| `tool.approval_required` | **承認ゲート**。`require_approval_for_tools` に該当するツール呼び出しが来た | `thread_id`, `tool_calls: [{id, source_event_id}]`(= 「今 / 済み」表示と `y/e/n` の対象) |
| `tool.response_required` | クライアント側で実行すべきツール(承認とは別。**`paste_to_cursor` はこちらではなく承認必須ツールとして `tool.approval_required` 経由になる想定**) | 同上 |
| `tool.response` | ツール実行結果がハーネス内で確定 | `tool_call_id`, `content` |
| `turn.done` | ターン終了(成功/エラー/キャンセル) | `state.status`, `state.message`(エラー時), `state.metrics` |

「`tool_call` 開始 / 終了」に対応させる実装ガイド(Step 05 向け): `model.message` の `tool_calls[]` に現れた時点で「実行中」、対応する `tool.response` (or 承認完了後の再開) が来たら「済み」と表示する。

### 承認の返し方(確認済み・型定義から)

承認要求 `tool.approval_required` を受け取ったら、**新しいターンとして** `user.tool_approval` を `input` に入れて POST する(そのターンの `previous_turn_id` は省略 = 自動で直前ターンに続く):

```bash
curl -s -X POST "http://localhost:8790/api/v1/sessions/$SID/turns" \
  -H "Content-Type: application/json" \
  -d '{
    "input": [
      { "type": "user.tool_approval", "thread_id": "main", "tool_call_id": "<tool_calls[0].id>", "approval": { "status": "allow" } }
    ]
  }'
```
- 却下: `"approval": { "status": "deny", "reason": "宛先が違う" }`(理由は必須ではないが付けると同セッションでエージェントに伝わり再生成を促せる。Step 05 の `n` フローはこれでよい)
- `e`(編集して承認)は TrueForge のプロトコルに専用フィールドが無い(確認済み: `ApprovalDecision` は allow/deny の 2 択のみ)。**推測される実装方針**: `n` として deny + 理由に編集後の希望を書いて再生成させる、または承認自体は `allow` しつつ Step 05 側 Paster に渡す `text` をローカルで上書きしてから貼り付ける(TrueForge には知らせない)。発注書の `y / e(編集) / n(理由)` はこのどちらかで実現する — **Step 05 で判断してよい(未確定)**
- ツール呼び出し結果(`tool.response_required` 系。クライアント実行ツール)は `user.tool_response`:
  ```json
  { "type": "user.tool_response", "thread_id": "main", "tool_call_id": "...", "content": "pasted" }
  ```

### エラー時の形(確認済み)

バリデーションエラー(400 系。実機で複数回観測):
```json
{"error":{"message":"✖ Unrecognized key: \"name\"\n  → at manifest\n..."}}
```
存在しないルート:
```json
{"error":{"message":"Route not found: PUT /api/v1/agents/xxx"}}
```
ターン内で LLM 呼び出し自体が失敗した場合(実機で観測。OpenAI キー不正のケース)は **HTTP 200 の SSE の中で `turn.done` の `state.status: "error"`** として届く(HTTP ステータスではなくイベント側で失敗を表現する。確認済み):
```json
{"type":"turn.done","state":{"status":"error","message":"Request failed (401): Incorrect API key ..."}}
```
→ Step 05 は `turn.done.state.status !== "done"` を失敗として扱うこと。

### Saved Agent の指定方法(確認済み)

- セッション作成時 `agent: { name: "aishow" }`(named/reference)。エージェント本体は Settings 側 or `POST /api/v1/agents` で一度作成しておく
- インライン一発利用も可能: `agent: { spec: AgentSpec }`(Step 05 では使わない想定。常に `aishow` を name 参照)

## MCP サーバー登録(確認済み・重要な制約)

**確認済み: TrueForge の MCP コネクタは "remote"(URL ベース)専用。ローカルの `command`/`args`/`env` を渡す stdio 起動はできない。** 実機で `type: "stdio", command: "npx", ...` を POST したところ即座に 400(`Unrecognized keys: "command","args","env"`, `expected "remote"`)。OpenAPI/SDK 型 (`McpServerType = "remote"`) とも一致。

```bash
curl -s -X POST http://localhost:8790/api/v1/settings/mcp-servers \
  -H "Content-Type: application/json" \
  -d '{"manifest":{"name":"dummy-remote","description":"dummy","type":"remote","url":"https://example.com/mcp"}}'
# => 200 { "data": { "name": "dummy-remote", "manifest": {...}, "auth_status": {"status":"not_required"} } }
```

Bright Data MCP は **ホスト版の streamable-HTTP エンドポイントがある**ので、これが `type: "remote"` にそのまま収まる(`harness/SETUP.md` の記録参照):
```
https://mcp.brightdata.com/mcp?token=<BRIGHTDATA_API_KEY>&groups=<GROUPS>
```
(このリポジトリの `.env` トークンをそのまま URL に埋めて実機登録するのは安全のため今回は控えた — SETUP.md に手順のみ記録。ローカルの `npx @brightdata/mcp`(stdio)は TrueForge に直接は繋がらない)

## Models / Skills エンドポイント(確認済み・参考)

- `POST /api/v1/settings/model-providers` の manifest は **snake_case**、well-known type(`openai` 等)は `name` フィールド不要(`type` がそのまま名前になる)。`auth.api_key` は文字列、`models[].{name, model_id, properties}` が必須:
  ```json
  {"manifest":{"type":"openai","auth":{"api_key":"sk-..."},"models":[{"name":"gpt-5.2","model_id":"gpt-5.2","properties":{}}]}}
  ```
  実機で 200 を確認。一覧取得時は `auth` 内の値がリダクトされる
- Skills の登録 API(`/api/v1/settings/skills` 等)は今回未実行(UI 操作前提のため)。`harness/SETUP.md` に UI 手順として記録

## 未確認・推測まとめ

| 項目 | 状態 |
|---|---|
| ベース URL 既定値・認証なし・SSE 形式・turn/session/agent の CRUD 全般 | **確認済み**(実機 curl) |
| MCP コネクタが remote URL 専用 | **確認済み**(実機 400 + SDK 型 + 公式ドキュメント抜粋) |
| Bright Data のホスト型 remote MCP URL が実際に TrueForge から動くこと | **未確認**(トークンを URL に載せて外部送信する実験は今回見送り。Step 01 の別セッションで手動確認を推奨) |
| `paste_to_cursor` 承認フローが `tool.approval_required` 経由で来ること | **推測**(`require_approval_for_tools` に載せたカスタムツールが同じイベント種別を通ることは型上自然だが、カスタム/ダミーツールを実際に MCP サーバーとして立てて確認はしていない) |
| 承認の `e`(編集)の扱い | **未確定**。プロトコルに専用フィールドなし。Step 05 側の設計判断が必要 |
| Skills(呪文)の TrueForge 側の具体的な登録フォーマット(SKILL.md のフロントマター等) | **推測**(`harness/spells/*.md` を `harness-skill-format.md` 相当のフロントマター無しでそのままインポートできる可能性が高いが未確認。UI での GitHub インポートを想定) |
