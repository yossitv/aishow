import AishowCore
import AppKit
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
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let state = AppState()
    private let hotKey = HotKey()
    private let recorder = PushToTalkRecorder()
    private let flame = FlameOverlay()
    private var flameMenuItem: NSMenuItem?

    /// ホットキー押下の瞬間に取った索敵結果(離すまで保持する)。
    private var pendingScan: ScanResult?

    /// 却下 → 再生成の残り回数(1 回の召喚あたり最大 2 回)。
    private var pendingRetriesLeft = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotKey()
        checkPermissionsOnFirstLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        flame.hide()
    }

    // MARK: - Status item / popover

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Aishow")
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "状態…", action: #selector(showStatusPopover), keyEquivalent: "")
        menu.addItem(withTitle: "設定…", action: #selector(showSettings), keyEquivalent: "")
        let flameItem = NSMenuItem(
            title: "詠唱中に炎の枠を表示",
            action: #selector(toggleFlameOverlay),
            keyEquivalent: ""
        )
        menu.addItem(flameItem)
        flameMenuItem = flameItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "終了", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu

        statusItem = item
    }

    @objc private func showStatusPopover() {
        state.refreshPermissions()
        presentPopover(content: AnyView(StatusView(state: state)))
    }

    @objc private func showSettings() {
        // 設定 UI は最小限(発注書の対象は常駐の殻)。System Settings への導線を提供する。
        presentPopover(content: AnyView(StatusView(state: state)))
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

    private func presentPopover(content: AnyView) {
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
        presentPopover(content: AnyView(view))
    }

    // MARK: - Permissions

    private func checkPermissionsOnFirstLaunch() {
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
        hotKey.onPermissionMissing = { [weak self] in
            Task { @MainActor in
                self?.state.setError("Accessibility 権限が無いためホットキーを監視できません")
                self?.showStatusPopover()
            }
        }
        hotKey.start()
    }

    /// 押した瞬間に scan する(自分の UI を出す前)。それから録音開始。
    private func handleHotKeyPress() {
        // Qodo #7-5: 既に scan〜summon が進行中(または承認待ち)なら新しい開始を無視する。
        guard !state.isBusy else { return }

        // 鉄則4: 最前面アプリの取得は自分の UI を出す前に行う。
        let scan = Pipeline.scanNow()
        pendingScan = scan

        state.setScanning()
        state.setRecording()
        recorder.start()
        // 焔(Step 08): 音声入力している間だけ画面の縁に炎を出す。
        // マイク権限が無く録音が始まらなかった場合は出さない(録音していないのに炎だけ出るのを防ぐ)。
        if recorder.isRecording {
            flame.show()
        }
    }

    private func handleHotKeyRelease() {
        flame.hide()

        guard let scan = pendingScan else { return }
        pendingScan = nil

        guard let audioURL = recorder.stop() else {
            state.setError("詠唱が短すぎるか、録音できませんでした")
            state.setIdle()
            return
        }

        state.setTranscribing()

        // Transcriber.transcribe は同期・ブロッキング(semaphore 待ち)なので、
        // MainActor 上の Task で直接呼ぶと文字起こし中 UI が固まる。バックグラウンドに逃がす。
        Task.detached {
            let result = Transcriber.transcribe(fileURL: audioURL)
            try? FileManager.default.removeItem(at: audioURL)
            switch result {
            case .success(let chant):
                await self.runSummon(scan: scan, chant: chant)
            case .failure(let error):
                await MainActor.run {
                    self.state.setError("文字起こしに失敗しました: \(error)")
                    self.state.setIdle()
                }
            }
        }
    }

    private func runSummon(scan: ScanResult, chant: String) async {
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
                        self?.state.setEvent(text)
                    }
                }
            )

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
            await MainActor.run {
                state.setError("召喚に失敗しました: \(error)")
                state.setIdle()
            }
        }
    }

    // MARK: - 承認 / 却下

    private func approve(_ approval: PendingApproval, editedText: String) {
        do {
            let result = try Paster.paste(
                text: editedText,
                appName: approval.pack.app,
                windowTitle: approval.pack.windowTitle
            )
            state.setCompleted("\(approval.site.workflow.rawValue) @ \(approval.site.domain ?? result.appName)")
        } catch {
            state.setError("貼り付けに失敗しました: \(error)")
        }
        popover?.performClose(nil)
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
            return
        }

        pendingRetriesLeft -= 1
        popover?.performClose(nil)
        state.setSummoning(approval.site.workflow.rawValue, domain: approval.site.domain)

        Task {
            do {
                let proposal = try await runner.regenerate(
                    pack: approval.pack,
                    site: approval.site,
                    reason: "却下。別案を",
                    onEvent: { [weak self] text in
                        Task { @MainActor in
                            self?.state.setEvent(text)
                        }
                    }
                )
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
                await MainActor.run {
                    state.setError("再生成に失敗しました: \(error)")
                    state.setIdle()
                }
            }
        }
    }
}
