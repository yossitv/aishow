import AishowCore
import AppKit
import Combine
import SwiftUI

/// メニューバー常駐アプリの殻。`aishow` を引数なしで起動するとこれが動く。
enum MenuBarApp {
    @MainActor
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // Dock アイコンを出さない
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        exit(0)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let state = AppState()
    /// 設定でホットキーを変えたら作り直す(HotKey は生成時に設定を読む)。
    private var hotKey = HotKey()
    /// Accessibility 許可待ちのポーリング(許可済みなら nil)。
    private var accessibilityPollTimer: Timer?
    private let recorder = PushToTalkRecorder()
    /// 詠唱中(録音中)に画面の縁を炎で囲う演出。
    private let flame = FlameOverlay()
    private var flameMenuItem: NSMenuItem?
    /// ノッチ裏でステータスアイコンが見えない環境向けの HUD(タスク1)。
    private lazy var hud = HUDPanel(state: state)
    /// ボタンが見えないとき承認 UI を出す通常ウィンドウ(key window になってよい)。
    private var approvalWindow: NSWindow?

    /// 進行中セッションの世代。× でキャンセルすると進み、古い世代の非同期結果(STT / 召喚)は捨てる。
    /// TrueForge / STT の送信は semaphore ブロッキングで協調キャンセルできないため、この世代番号で結果側を無効化する。
    private var sessionGeneration = 0
    private var sessionTask: Task<Void, Never>?

    /// ホットキー押下の瞬間に取った索敵結果(離すまで保持する)。
    private var pendingScan: ScanResult?

    /// 却下 → 再生成の残り回数(1 回の召喚あたり最大 2 回)。
    private var pendingRetriesLeft = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.write("起動 hotkey=\(HotKey.displayName) accessibility=\(AXIsProcessTrusted()) mic=\(PushToTalkRecorder.microphoneAuthorized)")
        setupStatusItem()
        hud.onCancel = { [weak self] in self?.cancelSession() }
        hud.setup()
        setupHotKey()
        checkPermissionsOnFirstLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        flame.hide()
    }

    /// ステータスバーのボタンが画面上で(ノッチの裏などに隠れず)実際に見えているか。
    private func isStatusButtonVisible() -> Bool {
        guard let button = statusItem?.button, let window = button.window, let screen = NSScreen.main else {
            return false
        }
        let screenFrame = screen.frame
        guard screenFrame.contains(window.frame) else { return false }

        // ノッチ範囲(auxiliaryTopLeftArea 〜 auxiliaryTopRightArea の間)にボタン中心が入っていないか。
        if let leftArea = screen.auxiliaryTopLeftArea, let rightArea = screen.auxiliaryTopRightArea {
            let buttonCenterX = window.frame.midX
            if buttonCenterX >= leftArea.maxX && buttonCenterX <= rightArea.minX {
                return false
            }
        }
        return true
    }

    // MARK: - Status item / popover

    private var languageCancellable: AnyCancellable?

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Aishow")
        }

        statusItem = item
        rebuildMenu()

        // 言語切り替え(Settings)を即時反映するため、NSMenu の項目名を作り直す。
        languageCancellable = L10n.shared.$language.dropFirst().sink { [weak self] _ in
            Task { @MainActor in
                self?.rebuildMenu()
                if self?.state.isBusy == false { self?.state.setIdle() } // currentLine の言語を更新
            }
        }
    }

    /// 言語変更時に呼び直し、NSMenu の各項目名を現在の言語で作り直す。
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: L10n.t("menu.status"), action: #selector(showStatusPopover), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("menu.settings"), action: #selector(showSettings), keyEquivalent: "")
        let flameItem = NSMenuItem(
            title: L10n.t("menu.flame"),
            action: #selector(toggleFlameOverlay),
            keyEquivalent: ""
        )
        menu.addItem(flameItem)
        flameMenuItem = flameItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L10n.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }
        statusItem?.menu = menu
    }

    @objc private func showStatusPopover() {
        state.refreshPermissions()
        if isStatusButtonVisible() {
            presentPopover(content: AnyView(StatusView(state: state)))
        } else {
            // ボタンが見えない(ノッチ裏等): popover の代わりに HUD に StatusView を載せる。
            hud.showDetail(content: AnyView(StatusView(state: state)))
        }
    }

    @objc private func showSettings() {
        let view = SettingsView(onHotKeyChanged: { [weak self] in self?.reapplyHotKey() })
        if isStatusButtonVisible() {
            presentPopover(content: AnyView(view))
        } else {
            hud.showDetail(content: AnyView(view))
        }
    }

    /// 設定変更後にホットキーを再登録する(再起動不要)。
    private func reapplyHotKey() {
        hotKey.stop()
        hotKey = HotKey()
        setupHotKey()
        if !state.isBusy { state.setIdle() } // 「Ready — hold X to chant」の X を更新
        AppLog.write("ホットキー変更 → \(HotKey.displayName)")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleFlameOverlay() {
        FlameOverlay.isEnabled.toggle()
        flameMenuItem?.state = FlameOverlay.isEnabled ? .on : .off
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        flameMenuItem?.state = FlameOverlay.isEnabled ? .on : .off
    }

    /// - Parameter makeKey: true なら自アプリをアクティブにして popover をキーにする(⏎ / Esc で操作させたいとき)。
    ///   最前面アプリの取得(鉄則4)は scan 時点で済んでいるので、ここでアクティブ化しても貼り付け先は失われない。
    private func presentPopover(content: AnyView, makeKey: Bool = false) {
        let popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: content)
        // Popover 自体の不透明な素材を消し、SwiftUI 側の Liquid Glass 表現をそのまま見せる。
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hosting
        self.popover = popover

        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if makeKey {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func presentApprovalPopover(_ approval: PendingApproval) {
        let view = ApprovalView(
            approval: approval,
            onApprove: { [weak self] editedText in
                self?.approve(approval, editedText: editedText)
            },
            onReject: { [weak self] in
                self?.reject()
            }
        )
        if isStatusButtonVisible() {
            presentPopover(content: AnyView(view), makeKey: true) // ⏎ で承認できるようにキーにする
        } else {
            // ボタンが見えない: 承認は人が操作する UI なので通常ウィンドウで key にする。
            // 貼り付け先(scannedApp)は scan 時点で既に確保済み(state.pendingApproval)なのでここでは変更しない。
            presentApprovalWindow(content: AnyView(view))
        }
    }

    /// ボタンが見えない環境向けの承認ウィンドウ。popover と異なり key window になってよい。
    private func presentApprovalWindow(content: AnyView) {
        let hosting = NSHostingController(rootView: content)
        // ウィンドウ自体の不透明な素材を消し、SwiftUI 側の Liquid Glass 表現をそのまま見せる。
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = L10n.t("approvalWindow.title")
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.delegate = self // 赤い閉じるボタン = キャンセル
        approvalWindow = window

        if let screen = NSScreen.main {
            let size = hosting.view.fittingSize
            let visible = screen.visibleFrame
            let x = visible.midX - size.width / 2
            let y = visible.maxY - size.height - 8
            window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Permissions

    private func checkPermissionsOnFirstLaunch() {
        Permissions.promptAccessibilityIfNeeded()
        state.refreshPermissions()
        Permissions.requestMicrophoneIfNeeded { [weak self] _ in
            Task { @MainActor in
                self?.state.refreshPermissions()
                if self?.state.permissions.accessibility == false
                    || self?.state.permissions.microphone == false
                    || self?.state.permissions.automation == false {
                    self?.showStatusPopover()
                }
            }
        }
    }

    // MARK: - HotKey → scan → 録音 → chant → summon

    private func setupHotKey() {
        hotKey.onPress = { [weak self] in
            self?.handleHotKeyPress()
        }
        hotKey.onRelease = { [weak self] in
            self?.handleHotKeyRelease()
        }
        hotKey.onCancel = { [weak self] in
            self?.handleHotKeyCancel()
        }
        hotKey.onPermissionMissing = { [weak self] in
            Task { @MainActor in
                self?.state.setError(L10n.t("error.accessibilityMissing"))
                self?.showStatusPopover()
                self?.startWaitingForAccessibility()
            }
        }
        hotKey.start()
    }

    /// Accessibility が許可されるまで 2 秒ごとに確認し、許可されたらアプリ再起動なしでホットキー監視を始める
    /// (VoiceInk と同じ挙動。システム設定でトグルをオンにした瞬間に使えるようになる)。
    private func startWaitingForAccessibility() {
        guard accessibilityPollTimer == nil else { return }
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            Task { @MainActor in
                guard let self else { return }
                self.accessibilityPollTimer = nil
                self.state.lastError = nil
                self.state.refreshPermissions()
                self.hotKey.start()
            }
        }
    }

    /// 押した瞬間に scan する(自分の UI を出す前)。それから録音開始。
    private func handleHotKeyPress() {
        // Qodo #7-5: 既に scan〜summon が進行中(または承認待ち)なら新しい開始を無視する。
        guard !state.isBusy else { return }

        // 録音は UI を出さないので scan より先に始めてよい(scan は osascript で 0.4〜1 秒かかり、
        // 後に回すと押した直後の声が落ちる)。
        recorder.start()

        // 焔(Step 08): 音声入力している間だけ画面の縁に炎を出す(録音が実際に始まった場合のみ)。
        // scan は main スレッドを 0.5〜1.5 秒ブロックするので、その前に出す(後に回すと押している間ほぼ見えない)。
        // パネルは非アクティブ化・クリック透過なので、最前面アプリの取得・⌘C には影響しない。
        if recorder.isRecording {
            flame.show()
        }

        // 鉄則4: 最前面アプリの取得は自分の UI を出す前に行う。
        let scanStarted = Date()
        let scan = Pipeline.scanNow()
        pendingScan = scan
        AppLog.write(String(format: "ホットキー押下 → scan 完了 %.2fs(%@ / %@)", Date().timeIntervalSince(scanStarted), scan.site.workflow.rawValue, scan.site.domain ?? "-"))

        state.setScanning()
        state.setRecording()
    }

    /// 長押し中に別キーが押された(⌘C 等の通常操作)。録音を破棄して待機に戻す。
    private func handleHotKeyCancel() {
        guard pendingScan != nil else { return }
        pendingScan = nil
        AppLog.write("長押し中に別キー → 録音を破棄")
        flame.hide()
        if let url = recorder.stop() {
            try? FileManager.default.removeItem(at: url)
        }
        state.setIdle()
    }

    private func handleHotKeyRelease() {
        flame.hide()

        guard let scan = pendingScan else { return }
        pendingScan = nil

        guard let audioURL = recorder.stop() else {
            AppLog.write("ホットキー解放 → 録音なし(短すぎ or 開始失敗)")
            state.setError(L10n.t("error.chantTooShort"))
            state.setIdle()
            return
        }

        state.setTranscribing()
        let generation = sessionGeneration

        // Transcriber.transcribe は同期・ブロッキング(semaphore 待ち)なので、
        // MainActor 上の Task で直接呼ぶと文字起こし中 UI が固まる。バックグラウンドに逃がす。
        sessionTask = Task.detached {
            let result = Transcriber.transcribe(fileURL: audioURL)
            try? FileManager.default.removeItem(at: audioURL)
            guard await self.isCurrentSession(generation) else { return } // × でキャンセル済み
            switch result {
            case .success(let chant):
                AppLog.write("STT 完了(\(chant.count) 文字)")
                await self.runSummon(scan: scan, chant: chant, generation: generation)
            case .failure(let error):
                AppLog.write("STT 失敗: \(error)")
                await MainActor.run {
                    self.state.setError(L10n.t("error.transcriptionFailed", "\(error)"))
                    self.state.setIdle()
                }
            }
        }
    }

    private func isCurrentSession(_ generation: Int) -> Bool {
        sessionGeneration == generation
    }

    /// HUD の × / 承認ウィンドウの閉じるボタン: 進行中のセッション(録音・文字起こし・召喚・承認待ち)を取り消す。
    private func cancelSession() {
        sessionGeneration += 1
        sessionTask?.cancel()
        sessionTask = nil
        pendingScan = nil
        flame.hide()
        if let url = recorder.stop() {
            try? FileManager.default.removeItem(at: url)
        }
        popover?.performClose(nil)
        closeApprovalWindow()
        state.setCancelled()
        AppLog.write("セッションをキャンセル")
    }

    private func closeApprovalWindow() {
        guard let window = approvalWindow else { return }
        approvalWindow = nil // windowWillClose でキャンセル扱いにしないため、先に外す
        window.close()
    }

    private func runSummon(scan: ScanResult, chant: String, generation: Int) async {
        pendingRetriesLeft = 2
        await MainActor.run {
            state.setSummoning(scan.site.workflow.rawValue, domain: scan.site.domain)
        }

        do {
            let proposal = try await Pipeline.summonRunner.summon(
                pack: scan.pack,
                site: scan.site,
                chant: chant,
                onEvent: { [weak self] text in
                    Task { @MainActor in
                        guard let self, self.isCurrentSession(generation) else { return } // × 後の進捗は捨てる
                        self.state.setEvent(text)
                    }
                }
            )

            guard await isCurrentSession(generation) else { return } // × でキャンセル済み
            AppLog.write("召喚完了 → 承認待ち")
            await MainActor.run {
                let approval = PendingApproval(
                    pack: scan.pack,
                    site: scan.site,
                    chant: chant,
                    proposal: proposal,
                    scannedApp: scan.pack.app
                )
                state.setAwaitingApproval(approval)
                presentApprovalPopover(approval)
            }
        } catch {
            guard await isCurrentSession(generation) else { return }
            AppLog.write("召喚失敗: \(error)")
            await MainActor.run {
                state.setError(L10n.t("error.summonFailed", "\(error)"))
                state.setIdle()
            }
        }
    }

    // MARK: - 承認 / 却下

    /// 承認: 貼り付け先(scan 時の最前面アプリ)を前面に戻し、クリップボード経由で ⌘V。Enter は送らない。
    private func approve(_ approval: PendingApproval, editedText: String) {
        AppLog.write("承認 → 貼り付け先 \(approval.pack.app)(\(editedText.count) 文字)")
        // 先に自分の UI を閉じる(承認ウィンドウが key のままだと貼り付け先を前面にできない)。
        popover?.performClose(nil)
        closeApprovalWindow()
        do {
            let result = try Paster.paste(
                text: editedText,
                appName: approval.pack.app,
                windowTitle: approval.pack.windowTitle
            )
            AppLog.write("貼り付け完了 → \(result.appName)")
            state.setCompleted("\(result.appName)")
        } catch {
            AppLog.write("貼り付け失敗: \(error)")
            state.setError(L10n.t("error.pasteFailed", "\(error)"))
        }
    }

    /// 却下: UI に理由入力が無いので固定文で再生成する(最大 2 回)。
    /// `TrueForgeSummonRunner` 以外(stub 等)では再生成をサポートせず、そのまま idle に戻す。
    private func reject() {
        guard let approval = state.pendingApproval,
              pendingRetriesLeft > 0,
              let runner = Pipeline.summonRunner as? TrueForgeSummonRunner else {
            state.pendingApproval = nil
            state.setIdle()
            popover?.performClose(nil)
            closeApprovalWindow()
            return
        }

        pendingRetriesLeft -= 1
        popover?.performClose(nil)
        closeApprovalWindow()
        state.setSummoning(approval.site.workflow.rawValue, domain: approval.site.domain)
        let generation = sessionGeneration

        sessionTask = Task {
            do {
                let proposal = try await runner.regenerate(
                    pack: approval.pack,
                    site: approval.site,
                    reason: "却下。別案を",
                    onEvent: { [weak self] text in
                        Task { @MainActor in
                            guard let self, self.isCurrentSession(generation) else { return } // × 後の進捗は捨てる
                            self.state.setEvent(text)
                        }
                    }
                )
                guard isCurrentSession(generation) else { return } // × でキャンセル済み
                await MainActor.run {
                    let newApproval = PendingApproval(
                        pack: approval.pack,
                        site: approval.site,
                        chant: approval.chant,
                        proposal: proposal,
                        scannedApp: approval.scannedApp
                    )
                    state.setAwaitingApproval(newApproval)
                    presentApprovalPopover(newApproval)
                }
            } catch {
                guard isCurrentSession(generation) else { return }
                await MainActor.run {
                    state.setError(L10n.t("error.regenerationFailed", "\(error)"))
                    state.setIdle()
                }
            }
        }
    }

    // MARK: - NSWindowDelegate(承認ウィンドウ)

    /// 承認ウィンドウの赤い閉じるボタン = キャンセル。approve/reject からの close は先に approvalWindow を外すので来ない。
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === approvalWindow else { return }
        approvalWindow = nil
        cancelSession()
    }
}
