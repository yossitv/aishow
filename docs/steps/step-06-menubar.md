# Step 06 — 常駐(`Aishow.app` メニューバーアプリ)

## 担当領域
- `Sources/aishow/App/`:
  - `AppMain.swift`: `NSApplication` + `setActivationPolicy(.accessory)`、`NSStatusItem`(メニューバー)。引数なしで起動されたら常駐モード、サブコマンド付きなら従来の CLI(1 バイナリ 2 モード)
  - `HotKey.swift`: グローバルホットキー `Option+Space`(Carbon `RegisterEventHotKey` または `NSEvent.addGlobalMonitorForEvents(.flagsChanged/.keyDown)`)。**押した瞬間に scan**(自分の UI を出す前)、押している間録音、離したら chant → summon
  - `StatusView.swift`(SwiftUI Popover): 常時 3 行「いま / 待ち / 済み」+ 直近のワークフロー名(`website_form @ acme.com`)
  - `ApprovalView.swift`: 本文(編集可)+ 根拠 URL + 貼り付け先(app / windowTitle)。`承認 / 編集して承認 / 却下(理由)`。承認前に最前面アプリが変わっていれば赤で警告
  - 設定: ホットキー、STT モデル、TrueForge URL(`UserDefaults`)。API キーは Keychain(`Security`)に保存し `.env` からの初回インポートを用意
- `make app`: release ビルド → `dist/Aishow.app`(`scripts/Info.plist.template`、`LSUIElement=true`、ad-hoc 署名)
- 初回起動: マイク / Accessibility / Automation の権限チェックと System Settings への導線

## 禁止事項
- Dock アイコンを出さない(`LSUIElement`)
- ホットキー押下 → scan の順序を崩さない(Popover を先に出すと最前面アプリが自分になる)
- 承認ポップオーバーを閉じただけで貼り付けない(明示的な承認ボタンのみ)

## 検収基準
- [ ] `make app && open dist/Aishow.app` → メニューバーにアイコン、Dock に出ない
- [ ] 初回起動でマイク・Accessibility・Automation の許可ダイアログ/導線が出る
- [ ] Chrome の Contact フォームで `Option+Space` 押しながら詠唱 → 離す → Popover に「索敵 ✔ / website_form @ domain / 召喚 / 調査中…」が順に出る
- [ ] 承認ポップオーバーで「編集して承認」→ 編集後の本文が Message 欄に入る
- [ ] 承認前に別アプリへ切り替えると警告が出て、そのままでは貼り付けられない
- [ ] `Aishow.app` を終了・再起動しても同じドメインのセッションが継続する
- [ ] デモ動画(3 分)を撮影できる状態
