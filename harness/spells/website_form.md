---
name: website_form
description: 企業サイトの問い合わせフォームに、その会社固有の事実を1つ以上引用したコールドメッセージ英文を書き、paste_to_cursor の承認待ちで止まる。ContextPack.url が問い合わせ/デモ/セールス系フォームのときに使う。
---
<!--
TrueForge の Settings → Skills は GitHub インポート(このリポジトリの harness/spells)または貼り付けで登録する(harness/SETUP.md 参照)。
フロントマターは name/description のみ必須という一般的な Skill 形式に合わせた。TrueForge 固有の追加フィールド
(例: allowed-tools 等)が要るかは UI ドキュメントからは確認できなかった(未確認)。動作しない場合はまず
フロントマターを外して本文だけで登録し、Import 側の要求に応じて追加する。
-->

# website_form — 企業サイトの問い合わせフォームにコールドメッセージ

前置: `_common.md`

## 手順
1. `ContextPack.url` の登録ドメイン `{domain}` を対象にする
2. サブエージェントで並列に調査(Bright Data MCP):
   - About: `scrape_as_markdown("https://{domain}/")`, `"https://{domain}/about"`
   - 製品: `"https://{domain}/products"` または `/product`, `/pricing`
   - ニュース: `search_engine("\"{domain}\" news 2026")`, `/blog`, `/news`
   - 構造化 collector(あれば): `bdata scraper run <COLLECTOR_ID> https://{domain}/`
3. 具体的な事実を **最低 1 つ**選ぶ(製品名 / 直近の発表 / 採用中の職種 / ミッション文)。引用元 URL を控える
4. フォームの文脈(`pageTitle` / `url` に Contact Sales / Partnership / Support / Demo)に合わせて 1 行目を変える
5. 本文を書く: 1 行目=なぜ今この会社か(事実の引用)、2 行目=詠唱者の提案(`chant` から)、3 行目=軽い CTA(15 分の会話など)。署名は入れない
6. 根拠 URL を箇条書き → 本文 → `paste_to_cursor({ text, target: { app, windowTitle } })` を呼ぶ(承認待ち。引数スキーマは `harness/tools.md` 参照。`target` は ContextPack の `app` / `windowTitle` をそのまま渡す)

## 失敗時
- サイトが取れない → `search_engine` のスニペットで書く。それも無理なら「調査不足: {domain} の情報が取れませんでした」と返し、`paste_to_cursor` は呼ばない
- collector の出力に `products` 等が欠ける → `scraper_heal(collectorId, "<症状>")` を提案し、`scraper_approve` は承認待ちにする
