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
- [ ] TrueForge チャット UI で `aishow` エージェントに「https://www.acme.com/contact を開いている。この会社に音声 SDK の話でコールドメッセージ」と打つと、Bright Data の tool_call が走り、サイトの事実を 1 つ以上引用した英文が返る
- [ ] 同エージェントが最後に `paste_to_cursor` を呼ぼうとして**承認待ち**で止まる(UI に承認ボタンが出る)
- [ ] `harness/SETUP.md` に、設定した Models / Connectors / Skills / 承認ツールがスクリーンショットか箇条書きで記録されている
- [ ] `CLAUDE.md` の「Bright Data scrapers」節に collector id と `run / heal / approve` コマンドが書かれている
- [ ] Skill 側で `paste_to_cursor` の引数スキーマが `{ text: string, target: { app: string, windowTitle: string } }` と定義されている(Step 05 の CLI がこの引数を受け取る)
