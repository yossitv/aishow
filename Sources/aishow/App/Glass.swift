import SwiftUI

/// Liquid Glass 風のカード修飾。macOS 26 以降は本物の `glassEffect`、
/// それより前の macOS ではガラス「風」の Material フォールバックを使う。
struct GlassCard: ViewModifier {
    var tint: Color?
    var cornerRadius: CGFloat = 16

    /// システム設定で「透明度を下げる」がオンなら、ガラス演出はやめて不透明背景にする。
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                )
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    tint.map { Glass.regular.tint($0) } ?? .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(0.12))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    /// このビューを Liquid Glass 風のカードで包む(内側 padding 込み)。
    func glassCard(tint: Color? = nil, cornerRadius: CGFloat = 16) -> some View {
        self
            .padding(10)
            .modifier(GlassCard(tint: tint, cornerRadius: cornerRadius))
    }

    /// ボタンに Liquid Glass 風のスタイルを適用する(macOS 26 未満は通常のボタンスタイルにフォールバック)。
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}
