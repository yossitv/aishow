# Step 01 — ハーネス(TrueForge + OpenAI + Bright Data MCP + 呪文)

## 担当領域
- `harness/SETUP.md` の手順で TrueForge をローカル起動し、以下を UI で設定する
  1. Settings → Models: **OpenAI**(`OPENAI_API_KEY`)。既定モデルは gpt-5 系、フォールバック gpt-4.1
  2. Settings → Connectors: **Bright Data MCP**(`npx @brightdata/mcp`、`API_TOKEN`、`GROUPS` は最小)
  3. Settings → Skills: `harness/spells/*.md` を Skill として登録(GitHub インポート or 貼り付け)
  4. Tools → 承認必須ツール: `paste_to_cursor`, `scraper_approve`
  5. "Save Agent" → 名前 `aishow`
- `harness/spells/website_form.md` を主呪文として完成させる(他の呪文は骨だけでよい)
- Bright Data の汎用「会社サイト構造化」collector を 1 つ作り、id を `CLAUDE.md` にピン留め

## 禁止事項
- Swift コードを触らない
- ログイン必須・有料壁のサイトをスクレイプしない

## 検収基準
- [ ] ❌ TrueForge チャット UI で `aishow` エージェントに「https://www.acme.com/contact を開いている。この会社に音声 SDK の話でコールドメッセージ」と打つと、Bright Data の tool_call が走り、サイトの事実を 1 つ以上引用した英文が返る
  - 未確認。理由: Bright Data MCP は TrueForge に **remote URL としてのみ**登録できる(stdio の `npx @brightdata/mcp` は実機で 400 になることを確認済み)。ホスト型 remote URL(`https://mcp.brightdata.com/mcp?token=...`)にトークンを載せて外部接続する検証は、キーを含む URL を外部ホストへ送信する操作になるため今回のセッションでは実行を控えた(サンドボックスのコマンド分類器にもブロックされた)。UI からの手動設定・動作確認は次工程(人間 or 別セッション)に持ち越し
- [ ] ❌ 同エージェントが最後に `paste_to_cursor` を呼ぼうとして**承認待ち**で止まる(UI に承認ボタンが出る)
  - 未確認。理由: `paste_to_cursor` は TrueForge 組み込みツールではなく自作 MCP サーバーとして提供する必要があり(`harness/tools.md` 参照)、そのサーバー自体は今回未実装(発注書 C は「最小構成案を書く」までが範囲と判断)。承認ゲートの仕組み自体(`AgentSpec.mcp_servers[].require_approval_for_tools` → `tool.approval_required` イベント)は API 実機検証で確認済み(`harness/trueforge-api.md`)
- [x] ✅ `harness/SETUP.md` に、設定した Models / Connectors / Skills / 承認ツールが記録されている(実機 API 検証込み。Bright Data の Connectors 手順は「remote URL 方式」に訂正した)
- [ ] ❌ `CLAUDE.md` の「Bright Data scrapers」節に collector id と `run / heal / approve` コマンドが書かれている
  - 未確認。理由: このハーネス環境に `bdata` CLI が無く、Bright Data の管理画面/アカウント操作をする手段が無かったため collector 自体を作成できなかった。`run/heal/approve` コマンド書式は既存の `CLAUDE.md` に記載済みで変更不要、id のみ空欄
- [x] ✅ Skill 側で `paste_to_cursor` の引数スキーマが `{ text: string, target: { app: string, windowTitle: string } }` と定義されている(`harness/tools.md` に JSON Schema で明記、`harness/spells/website_form.md` からも参照)
