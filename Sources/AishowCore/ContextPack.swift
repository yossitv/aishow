import Foundation

/// 詠唱時点の PC コンテキスト(索敵の結果)。TrueForge に渡す入力の元。
/// Step 2 で `scan` が生成する。ここではデータ型のみ定義。
public struct ContextPack: Codable, Equatable, Sendable {
    public var app: String
    public var windowTitle: String?
    public var url: String?
    public var pageTitle: String?
    public var selectedText: String?
    public var focusedInput: Bool
    public var hasFormTextarea: Bool
    public var chant: String?
    public var capturedAt: Date

    public init(
        app: String,
        windowTitle: String? = nil,
        url: String? = nil,
        pageTitle: String? = nil,
        selectedText: String? = nil,
        focusedInput: Bool = false,
        hasFormTextarea: Bool = false,
        chant: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.app = app
        self.windowTitle = windowTitle
        self.url = url
        self.pageTitle = pageTitle
        self.selectedText = selectedText
        self.focusedInput = focusedInput
        self.hasFormTextarea = hasFormTextarea
        self.chant = chant
        self.capturedAt = capturedAt
    }
}
