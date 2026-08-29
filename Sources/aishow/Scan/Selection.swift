import AppKit
import ApplicationServices
import Foundation

/// 現在の選択テキストをクリップボード経由(Cmd+C)で取得する。
/// クリップボードは必ず退避・復元する。
enum Selection {
    /// Accessibility 権限が無ければ stderr に案内を出し nil を返す。
    static func capture() -> String? {
        guard AXIsProcessTrusted() else {
            FileHandle.standardError.write(
                """
                aishow: Accessibility 権限が無いため選択テキストを取得できません。\
                「システム設定 > プライバシーとセキュリティ > アクセシビリティ」で aishow を許可してください。\n
                """.data(using: .utf8)!
            )
            return nil
        }

        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount
        let savedItems = capturePasteboardContents(pasteboard)

        defer {
            restorePasteboard(pasteboard, items: savedItems)
        }

        pasteboard.clearContents()

        sendCmdC()

        // Cmd+C がクリップボードに反映されるまで待つ
        Thread.sleep(forTimeInterval: 0.15)

        guard pasteboard.changeCount != savedChangeCount else {
            return nil
        }

        return pasteboard.string(forType: .string)
    }

    private static func capturePasteboardContents(_ pasteboard: NSPasteboard) -> [[String: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            return dict
        }
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [[String: Data]]) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let newItems = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(newItems)
    }

    private static func sendCmdC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCodeC: CGKeyCode = 8 // 'c'

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeC, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
