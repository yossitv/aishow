import AppKit
import Combine
import SwiftUI

/// ノッチ裏でメニューバーが見えない環境向けの状態表示 HUD。
///
/// `NSPanel`(nonactivating + HUD スタイル)をメインスクリーンの `visibleFrame` 上端中央、
/// ノッチの下(上端から 8pt)に浮かせる。最前面アプリのフォーカスを奪わないよう
/// `orderFrontRegardless()` のみ使い、`makeKeyAndOrderFront` は使わない。
///
/// 通常時(`.compact`)は `currentLine` / `lastError` の 1〜2 行を表示し、
/// ステータスボタンが隠れている環境では `.detail` モードで `StatusView` をそのまま載せる
/// (`MenuBarApp` の `showStatusPopover` から切り替える)。
@MainActor
final class HUDPanel {
    enum Mode {
        case compact
        case detail(AnyView)
    }

    private let state: AppState
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?
    private var hideWorkItem: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    private var isShowingDetail = false

    /// × ボタンが押されたとき(進行中セッションの取り消し)。`MenuBarApp` が結線する。
    var onCancel: (() -> Void)?

    init(state: AppState) {
        self.state = state
    }

    /// `applicationDidFinishLaunching` から呼ぶ。パネル自体は生成するが最初は隠れている。
    func setup() {
        let panel = makePanel()
        self.panel = panel
        installCompactContent()

        // AppState の変化を購読して表示/非表示を切り替える(idle 以外で表示、idle に戻ったら 1.5 秒後に隠す)。
        cancellable = state.objectWillChange.sink { [weak self] _ in
            // objectWillChange は変更「前」に飛ぶので、次のランループで見る。
            DispatchQueue.main.async {
                self?.reflectState()
            }
        }
        reflectState()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 44),
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        return panel
    }

    private func installCompactContent() {
        guard let panel else { return }
        let view = HUDCompactView(state: state, onCancel: { [weak self] in self?.onCancel?() })
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
    }

    /// 承認 UI 等、`StatusView` をそのまま載せたいときに使う「詳細」モード。
    /// ボタン(ステータスアイテム)が見えない環境で popover の代わりに使う。
    func showDetail(content: AnyView) {
        guard let panel else { return }
        isShowingDetail = true
        let hosting = NSHostingView(rootView: content.frame(width: 320))
        panel.contentView = hosting
        reposition(panel: panel, size: hosting.fittingSize)
        panel.orderFrontRegardless()
        hideWorkItem?.cancel()
        installOutsideClickMonitor()
    }

    /// 詳細モードを終えて通常の compact 表示に戻す。
    func restoreCompact() {
        isShowingDetail = false
        removeOutsideClickMonitor()
        installCompactContent()
        reflectState()
    }

    /// 詳細モード表示中に panel 外をクリックしたら compact 表示に戻す(popover の transient 挙動の代替)。
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.restoreCompact()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    private func reflectState() {
        guard let panel else { return }
        guard !isShowingDetail else { return } // 詳細モード表示中は compact の自動表示/非表示ロジックを無視
        hideWorkItem?.cancel()

        if state.isBusy || state.pendingApproval != nil || state.lastError != nil {
            reposition(panel: panel, size: panel.contentView?.fittingSize ?? NSSize(width: 320, height: 44))
            panel.orderFrontRegardless()
        } else {
            // idle: 1.5 秒後に隠す(直後の完了メッセージなどをすぐ消さない)。
            let work = DispatchWorkItem { [weak panel] in
                panel?.orderOut(nil)
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    /// メインスクリーンの `visibleFrame` 上端中央、上端から 8pt 下に配置する。
    private func reposition(panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(max(size.width, 200), 480)
        let height = max(size.height, 36)
        let x = visible.midX - width / 2
        let y = visible.maxY - height - 8
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

/// HUD の通常表示: 「いま」の 1 行 + エラー(あれば)。
private struct HUDCompactView: View {
    @ObservedObject var state: AppState
    let onCancel: () -> Void

    private var canCancel: Bool {
        state.isBusy || state.pendingApproval != nil || state.lastError != nil
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .center, spacing: 2) {
                Text(state.currentLine)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let error = state.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            if canCancel {
                // × でセッション(録音 / 文字起こし / 召喚 / 承認待ち / エラー表示)を取り消す
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 480)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
