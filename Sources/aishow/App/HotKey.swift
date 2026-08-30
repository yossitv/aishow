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
    /// kVK_Function。Fn(🌐)単独モードで `flagsChanged` イベントの keyCode として使う。
    private static let functionKeyCode: UInt16 = 63
    /// kVK_Command / kVK_RightCommand。
    private static let leftCommandKeyCode: UInt16 = 55
    private static let rightCommandKeyCode: UInt16 = 54
    static let modifiersDefaultsKey = "hotKeyModifiers"

    /// 修飾キー単独の長押しモード(Space を併用しない)。`flagsChanged` で押下/解放を見る。
    struct HoldKey {
        let keyCodes: Set<UInt16>
        let flag: NSEvent.ModifierFlags
        let name: String
    }

    /// `UserDefaults` の `hotKeyModifiers` が単独長押しモードを指していればその定義を返す。
    /// - `fn` / `function` / `globe`: Fn(🌐)キー
    /// - `cmd` / `command`: 左右どちらの Command キーでも
    /// - `rcmd` / `lcmd`: 右 / 左の Command キーのみ
    static var holdKey: HoldKey? {
        let raw = (UserDefaults.standard.string(forKey: modifiersDefaultsKey) ?? "").lowercased()
        switch raw {
        case "fn", "function", "globe":
            return HoldKey(keyCodes: [functionKeyCode], flag: .function, name: "Hold Fn (🌐)")
        case "cmd", "command":
            return HoldKey(keyCodes: [leftCommandKeyCode, rightCommandKeyCode], flag: .command, name: "Hold ⌘")
        case "rcmd", "rcommand":
            return HoldKey(keyCodes: [rightCommandKeyCode], flag: .command, name: "Hold Right ⌘")
        case "lcmd", "lcommand":
            return HoldKey(keyCodes: [leftCommandKeyCode], flag: .command, name: "Hold Left ⌘")
        default:
            return nil
        }
    }

    /// Fn(🌐)単独モードか(StatusView の注意書き表示用)。
    static var isFnMode: Bool { holdKey?.flag == .function }

    /// `UserDefaults` から修飾キーを読む。未設定・不正なら `.option`。Fn モード時は使わない。
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

    /// 表示用ラベル(例: `Control+Option+Space` / `Fn(🌐)`)。
    static var displayName: String {
        if let hold = holdKey { return hold.name }
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
    private let holdKey = HotKey.holdKey

    private var monitor: Any?
    private var isDown = false

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onPermissionMissing: (() -> Void)?
    /// 単独長押しモードで、押している間に別のキーが押された(= 通常のショートカット操作だった)ときに呼ぶ。
    /// 呼び出し側は録音を破棄して待機に戻す。
    var onCancel: (() -> Void)?

    /// 監視を開始する。Accessibility 権限が無ければ案内コールバックを呼んで何もしない。
    func start() {
        guard AXIsProcessTrusted() else {
            onPermissionMissing?()
            return
        }
        guard monitor == nil else { return }

        if holdKey != nil {
            // 単独長押しモード(Fn / ⌘)。Fn の場合はシステム設定で「🌐キーを押して: 何もしない」にする必要がある
            // (既定の入力ソース切替等が割り当てられていると flagsChanged が奪われる)。
            // keyDown も見て、長押し中に別キーが押されたら(⌘C 等の通常操作)録音を中止する。
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                // scan(⌘C)/ cast(⌘V)で自分が送った合成キーは無視する。
                if SyntheticKeyEvent.isOwn(event) { return }
                if event.type == .keyDown {
                    self?.handleKeyDownWhileHolding()
                } else {
                    self?.handleFlagsChanged(event)
                }
            }
        } else {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        pendingHold?.cancel()
        pendingHold = nil
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

    /// 単独長押しモードの長押し判定時間。これより短い押下(⌘C 等の通常操作)は無視する。
    static let holdDelay: TimeInterval = 0.35

    /// 長押し判定待ちのタイマー。
    private var pendingHold: DispatchWorkItem?

    /// 単独長押しモード。対象キーを `holdDelay` 以上単独で押し続けたら `onPress`、離したら `onRelease`。
    /// 判定前に離した/別キーを押した場合は何もしない(通常のショートカット操作として素通し)。
    private func handleFlagsChanged(_ event: NSEvent) {
        guard let hold = holdKey, hold.keyCodes.contains(event.keyCode) else { return }
        let isHeld = event.modifierFlags.contains(hold.flag)
        if isHeld {
            guard !isDown, pendingHold == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pendingHold != nil else { return }
                self.pendingHold = nil
                self.isDown = true
                self.onPress?()
            }
            pendingHold = work
            DispatchQueue.main.asyncAfter(deadline: .now() + HotKey.holdDelay, execute: work)
        } else {
            if let pending = pendingHold {
                pending.cancel()
                pendingHold = nil // 判定前に離した → 通常操作
            }
            if isDown {
                isDown = false
                onRelease?()
            }
        }
    }

    /// 単独長押し中(または判定待ち中)に別キーが押された = 通常のショートカット操作。
    private func handleKeyDownWhileHolding() {
        if let pending = pendingHold {
            pending.cancel()
            pendingHold = nil
            return
        }
        guard isDown else { return }
        isDown = false
        onCancel?()
    }
}
