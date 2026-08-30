import AppKit
import Foundation

/// `aishow flame [--seconds N]` — Accessibility 権限やホットキーなしで炎の演出を検収するためのデバッグコマンド。
/// `FlameOverlay.isEnabled` の設定を無視して必ず表示する。
enum FlameCommand {
    @MainActor
    static func run(_ args: [String]) -> Never {
        let seconds = parseSeconds(args) ?? 3.0

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let overlay = FlameOverlay()
        let wasEnabled = FlameOverlay.isEnabled
        FlameOverlay.isEnabled = true // 検収用: 設定を無視して必ず表示する
        overlay.show()

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            overlay.hide()
            FlameOverlay.isEnabled = wasEnabled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                exit(0)
            }
        }

        app.run()
        exit(0)
    }

    private static func parseSeconds(_ args: [String]) -> Double? {
        var index = 0
        while index < args.count {
            if args[index] == "--seconds", index + 1 < args.count {
                return Double(args[index + 1])
            }
            index += 1
        }
        return nil
    }
}
