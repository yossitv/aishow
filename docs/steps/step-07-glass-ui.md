# Step 07 — 硝子(Liquid Glass 風 UI)

Apple の新デザイン言語 [Liquid Glass](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)(WWDC25)に合わせて、Popover の見た目を「半透明のガラス素材が周囲を反射・屈折し、コントロールがコンテンツの上に一層浮く」ものにする。**見た目だけ**の Step。承認フロー・貼り付けロジックには触らない。Best UI 軸(iPad)の加点狙い。

参考にする性質(記事より):
- 半透明素材が周囲を **反射・屈折**(specular highlight)、色は周囲のコンテンツに引きずられる
- コントロールは **角丸と同心(concentric)** な丸み、矩形ではない
- コントロール層は **コンテンツの上に浮く機能層**、コンテンツに譲る
- ライト / ダーク両対応、tint あり / clear
- 必要に応じて **動的に変形(morph)** する

環境: 開発機は macOS 26.5 / Xcode 26 → SwiftUI の `glassEffect(_:in:)` / `GlassEffectContainer` / `.buttonStyle(.glass)` が使える。Package は `macOS(.v14)` のままなので **`if #available(macOS 26, *)` で分岐し、旧 OS は `.ultraThinMaterial` にフォールバック**する。

## 担当領域
- `Sources/aishow/App/Glass.swift`(新規):
  - `GlassCard` ViewModifier: `macOS 26` では `.glassEffect(.regular.tint(色).interactive(), in: .rect(cornerRadius: 16))`、それ以外は `.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))` + 細い白ストローク(`Color.white.opacity(0.25)`)
  - `GlassButtonStyle` 相当: 26 では `.glass` / `.glassProminent`、旧 OS では `.bordered` / `.borderedProminent`
  - `@Environment(\.accessibilityReduceTransparency)` が true なら不透明 `.regularMaterial` に落とす
- `StatusView.swift`: 3 行「いま / 待ち / 済み」を **1 枚ずつのガラスカード**に。tint は状態で変える(いま=`.blue`、待ち=`.orange`、済み=`.green`、エラー=`.red`)。値の更新は `contentTransition(.numericText())` / `.animation(.smooth)` で滑らかに。外側は `GlassEffectContainer(spacing:)` にまとめ、カード同士が近づいたとき一体化(`glassEffectUnion`)する
- `ApprovalView.swift`: 根拠 URL / 本文 / 貼り付け先 の各セクションをガラスカードに。**本文 `TextEditor` の背景だけは不透明**(可読性)。「承認」は `.glassProminent`、「却下」は `.glass`。「それでも貼る」警告カードは赤 tint
- `MenuBarApp.swift` `presentPopover`: `NSHostingController` の view と `popover.contentViewController?.view.layer?.backgroundColor` を clear にし、SwiftUI 側のガラスが Popover の素材の上に乗るようにする。角丸は Popover の角と同心になるよう padding を揃える(外側 12pt → カード角丸 16pt)
- `docs/screenshots/status-glass.png`、`approval-glass.png`(ライト・ダーク各 1 枚、計 4 枚まで)。README の UI 節に貼る

任意(時間があれば): `NSPopover` を borderless `NSPanel`(`.nonactivatingPanel`, `.fullSizeContentView`, `isOpaque = false`, `backgroundColor = .clear`)に置き換えて Popover の矢印と枠を消し、ガラス 1 枚が浮いているだけの見た目にする。**ホットキー → scan の順序と `transient` 相当の閉じ方(外クリックで閉じる)は維持**。

## 禁止事項
- 承認・却下・「それでも貼る」の **ロジック・順序・ボタン配置(却下=左、承認=右・デフォルトアクション)を変えない**
- `swift build`(macOS 14 ターゲット)を壊さない。26 専用 API は必ず `#available` の中
- 色をハードコードしない(ライト / ダークは素材と tint に任せる)。文字色は `.primary` / `.secondary` のみ
- ガラスの上に長文を直接置かない(本文エディタは不透明背景)。コントラストを落として可読性を犠牲にしない
- Reduce Transparency ON のユーザーに透明を強制しない
- `AishowCore` を触らない(見た目だけの Step)

## 検収基準
- [ ] `swift build && swift test` が通る(Core のテストは無変更で全通過)
- [ ] `make app && open dist/Aishow.app` → macOS 26 で Popover の背景が透け、背後のウィンドウ / 壁紙の色が映る。カードは角丸で Popover の角と同心
- [ ] システム設定でライト ⇄ ダークを切り替えても崩れない(文字が読める、tint が両方で見える)
- [ ] アクセシビリティ「透明度を下げる」ON で不透明になり、レイアウトは同じ
- [ ] 「いま / 待ち / 済み」の更新がアニメーションで切り替わる(パッと置き換わらない)
- [ ] 承認 Popover で「却下 / 承認 / それでも貼る」の動作が Step 06 の検収と同一(貼り付け結果・警告フロー変化なし)
- [ ] `docs/screenshots/` にライト / ダークのスクリーンショット、README に掲載
- [ ] PR に Qodo `/agentic_review` を通してマージ
