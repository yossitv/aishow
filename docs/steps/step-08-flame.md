# Step 08 — 焔(詠唱中の炎の枠)

ホットキーを**押している間**(= 詠唱中・録音中)、画面全体の縁を「メラメラとした火」が囲う演出を入れる。魔法を読み上げている感じを出すための **見た目だけ**の Step。設定で ON / OFF できる(既定 ON)。scan → 録音 → 文字起こし → 召喚 → 承認のロジックには触らない。

技術方針(調査済み): 各ディスプレイに 1 枚ずつ、透明・クリック透過・フォーカスを奪わない borderless `NSPanel` を最前面に出し、その上に `CAEmitterLayer` のパーティクルで炎を描く。追加の権限・外部 SDK は不要。

## 担当領域

### `Sources/aishow/App/FlameOverlay.swift`(新規)
- `@MainActor final class FlameOverlay`
  - `static let enabledDefaultsKey = "flameOverlayEnabled"`、`static var isEnabled: Bool { get set }`(`UserDefaults.standard`。**未設定は true**。`object(forKey:) == nil` を既定 true と読む)
  - `func show()`: `isEnabled` が false なら何もしない。`NSScreen.screens` ごとに `FlamePanel` を作って `orderFrontRegardless()`、alpha 0 → 1 を 0.25 秒でフェードイン。既に表示中なら何もしない
  - `func hide()`: alpha 1 → 0 を 0.35 秒でフェードアウトし、完了後 `orderOut(nil)` して破棄。パーティクルは `birthRate = 0` にしてから消す(残り火が自然に消える)
  - `NSApplication.didChangeScreenParametersNotification` を購読し、表示中にディスプレイ構成が変わったら作り直す
- `FlamePanel: NSPanel`
  - `styleMask: [.borderless, .nonactivatingPanel]`、`isOpaque = false`、`backgroundColor = .clear`、`hasShadow = false`
  - `ignoresMouseEvents = true`(クリックは下のアプリへ素通し)
  - `level = .screenSaver`、`collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`
  - `contentRect` は `screen.frame`(`visibleFrame` ではない。メニューバー・ノッチ周りも覆う)
  - `canBecomeKey` / `canBecomeMain` を **false** にオーバーライド(フォーカスを絶対に奪わない。鉄則4 の前提を守る)
- `FlameView: NSView`(`wantsLayer = true`)
  - 四辺それぞれに `CAEmitterLayer` を置く(`emitterShape = .line`、辺に沿って `emitterSize`。上辺は下向き、下辺は上向き、左右は内向きに炎が立つ。**下辺が主役**で最も濃く、上辺は控えめに)
  - `CAEmitterCell`: 円形のソフトなグラデーション画像(`CGContext` でその場で描く。画像アセットを足さない)、`lifetime` 0.6〜1.2 秒、`velocity` 80〜160 pt/s、`emissionRange` ±0.3 rad、`scale` 0.4→0(`scaleSpeed` 負)、`alphaSpeed` 負、色は **赤(下)→ 橙 → 黄(先端)** になるよう `color` + `redRange / greenRange` で揺らす。`yAcceleration` で上向きの浮力
  - 炎の帯は縁から **80〜120 pt** 程度に収める(中央の作業領域・Popover を邪魔しない)
  - `birthRate` は 1 辺あたり合計 **300〜600 個/秒**を目安(5K でも軽く)。`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` が true のときはパーティクルを出さず、**静的な赤橙のグロー枠**(`CAGradientLayer` か shadow 付き枠)だけを表示する
  - 任意: `func setIntensity(_ level: Float)`(0〜1)で `birthRate` / `velocity` をスケールできるようにしておく(将来の声量連動用。今回は配線しない)

### `Sources/aishow/App/MenuBarApp.swift`
- `AppDelegate` に `private let flame = FlameOverlay()` を追加
- `handleHotKeyPress()`: **`Pipeline.scanNow()` → `state.setScanning()/setRecording()` → `recorder.start()` の後**に `flame.show()`(鉄則4: 自分の UI は scan の後)。`guard !state.isBusy` で早期 return する経路では出さない
- `handleHotKeyRelease()`: 先頭で `flame.hide()`(`pendingScan` が nil でも呼ぶ。押しっぱなし解除経路で炎が残らないように)
- メニューに **`詠唱中に炎の枠を表示`** チェック項目を追加(「設定…」の直後、区切り線の前)。`state = FlameOverlay.isEnabled ? .on : .off`、選択で反転して `UserDefaults` に保存、`NSMenuDelegate.menuNeedsUpdate` か `validateMenuItem` で開くたびに現在値を反映
- `applicationWillTerminate` で `flame.hide()`(念のため)

### `Sources/aishow/Commands/FlameCommand.swift`(新規)+ `main.swift`
- デバッグ用サブコマンド `aishow flame [--seconds N]`(既定 3 秒): `NSApplication` を `.accessory` で立てて `FlameOverlay.show()` → N 秒後 `hide()` → 終了(exit 0)。**`isEnabled` を無視して必ず表示する**(動作確認用)。`help` の一覧にも 1 行追加
- 目的: Accessibility 権限やホットキーなしで、`screencapture` で見た目を検収できるようにする

### `README.md`
- UI 節に「詠唱中は画面の縁に炎が出る。メニューの『詠唱中に炎の枠を表示』または `defaults write com.openhome.aishow flameOverlayEnabled -bool false` で OFF」を追記
- `aishow flame` をコマンド一覧に追記

## 禁止事項
- 承認・却下・貼り付け・scan の **ロジック・順序を変えない**。`FlameOverlay` は `show()` / `hide()` の副作用しか持たず、`AppState` を読まない・書かない
- `AishowCore` を触らない
- パネルがフォーカス・キー入力・クリックを奪わない(`canBecomeKey = false`、`ignoresMouseEvents = true` を外さない)
- 画像・動画・音声アセットを追加しない(パーティクル画像はコードで生成)。外部 SDK・依存を追加しない
- `swift build`(macOS 14 ターゲット)を壊さない。macOS 15+ 専用 API を使う場合は `#available` の中
- 押していないときに何も残さない(`hide()` 後にウィンドウ・タイマー・通知購読が漏れない)
- Reduce Motion ON のユーザーに激しいアニメーションを強制しない

## 検収基準
- [ ] `swift build && swift test` が通る(Core のテストは無変更で全通過)
- [ ] `.build/debug/aishow flame --seconds 3` で、全ディスプレイの縁に炎が 3 秒出て消え、プロセスが exit 0 で終わる(その間 `screencapture -x` で撮ったスクリーンショットに炎が映る)
- [ ] 炎の表示中も最前面アプリのフォーカスが移らず、クリック・キー入力が下のアプリに届く
- [ ] `make app && open dist/Aishow.app` → ホットキーを押している間だけ炎が出て、離すとフェードアウトする。scan → 録音 → 承認の挙動は Step 06 の検収と同一
- [ ] メニュー「詠唱中に炎の枠を表示」のチェックを外すと炎が出ない。再起動後も設定が保持される。`defaults write com.openhome.aishow flameOverlayEnabled -bool false` でも OFF になる
- [ ] システム設定「視差効果を減らす」ON で、パーティクルではなく静的なグロー枠になる
- [ ] `docs/screenshots/flame.png`(1 枚)、README に掲載
- [ ] PR に Qodo `/agentic_review` を通してマージ
