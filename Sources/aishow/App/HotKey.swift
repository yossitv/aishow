import AppKit
import Foundation

/// グローバルホットキー(既定 `Option+Space`)。
///
/// 修飾キーは `UserDefaults` の `hotKeyModifiers`(例: `"control+option"`)で変更できる。
/// ChatGPT デスクトップ等が `Option+Space` を占有している環境向け。
///
/// 発注書の鉄則(ホットキー押下 → scan の順序を崩さない): `onPress` は
/// **自分の UI を出す前**に呼ばれる前提で、呼び出し側(`MenuBarApp`)がまず
/// `Pipeline.scanNow()` を呼び、それから Popover を出す・録音を開始する。
///
/// `NSEvent.addGlobalMonitorForEvents` は Accessibility 権限(`AXIsProcessTrusted()`)
/// が無いとイベントを受け取れない。権限が無い場合は `onPermissionMissing` を呼ぶ。
final class HotKey {
    private static let spaceKeyCode: UInt16 = 49
    static let modifiersDefaultsKey = "hotKeyModifiers"

    /// `UserDefaults` から修飾キーを読む。未設定・不正なら `.option`。
    static func configuredModifiers() -> NSEvent.ModifierFlags {
        let raw = UserDefaults.standard.string(forKey: modifiersDefaultsKey) ?? "option"
        var flags: NSEvent.ModifierFlags = []
        for part in raw.lowercased().split(whereSeparator: { "+ ,".contains($0) }) {
            switch part {
            case "option", "alt", "opt": flags.insert(.option)
            case "control", "ctrl": flags.insert(.control)
            case "command", "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        return flags.isEmpty ? [.option] : flags
    }

    /// 表示用ラベル(例: `Control+Option+Space`)。
    static var displayName: String {
        let f = configuredModifiers()
        var parts: [String] = []
        if f.contains(.control) { parts.append("Control") }
        if f.contains(.option) { parts.append("Option") }
        if f.contains(.shift) { parts.append("Shift") }
        if f.contains(.command) { parts.append("Command") }
        parts.append("Space")
        return parts.joined(separator: "+")
    }

    private let requiredModifiers = HotKey.configuredModifiers()

    private var monitor: Any?
    private var isDown = false

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onPermissionMissing: (() -> Void)?

    /// 監視を開始する。Accessibility 権限が無ければ案内コールバックを呼んで何もしない。
    func start() {
        guard AXIsProcessTrusted() else {
            onPermissionMissing?()
            return
        }
        guard monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isDown = false
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == HotKey.spaceKeyCode else { return }
        let mods = event.modifierFlags.intersection([.option, .control, .command, .shift])
        guard mods == requiredModifiers else {
            // 修飾キーを離した/押していない状態で Space が来た場合、押しっぱなし扱いを解除する。
            if isDown, event.type == .keyUp {
                isDown = false
                onRelease?()
            }
            return
        }

        switch event.type {
        case .keyDown:
            guard !isDown else { return } // オートリピートを無視
            isDown = true
            onPress?()
        case .keyUp:
            guard isDown else { return }
            isDown = false
            onRelease?()
        default:
            break
        }
    }
}
