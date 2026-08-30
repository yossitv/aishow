import AppKit
import QuartzCore

/// 詠唱中(ホットキー押下中)に画面の縁を炎で囲う演出。**見た目だけ**。
/// `AppState` を読み書きしない。show()/hide() の副作用のみを持つ。
@MainActor
final class FlameOverlay {
    static let enabledDefaultsKey = "flameOverlayEnabled"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledDefaultsKey) == nil {
                return true // 未設定は既定 ON
            }
            return UserDefaults.standard.bool(forKey: enabledDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey)
        }
    }

    private var panels: [FlamePanel] = []
    private var isVisible = false
    private var screenObserver: NSObjectProtocol?

    func show() {
        guard Self.isEnabled else { return }
        guard !isVisible else { return }
        isVisible = true

        rebuildPanels()

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildPanels()
                }
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        let panelsToClose = panels
        panels = []

        for panel in panelsToClose {
            (panel.contentView as? FlameView)?.stopEmitting()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            for panel in panelsToClose {
                panel.animator().alphaValue = 0
            }
        } completionHandler: {
            for panel in panelsToClose {
                panel.orderOut(nil)
            }
        }
    }

    private func rebuildPanels() {
        guard isVisible else { return }

        let oldPanels = panels
        panels = []

        for screen in NSScreen.screens {
            let panel = FlamePanel(screen: screen)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            for panel in panels {
                panel.animator().alphaValue = 1
            }
        }

        for panel in oldPanels {
            panel.orderOut(nil)
        }

        // 呼び出し側(ホットキー押下)はこの直後に同期 scan で main スレッドを 1 秒前後ブロックする。
        // 明示的に commit しないと scan が終わるまで炎が描かれない。
        CATransaction.flush()
    }
}

/// 透明・クリック透過・フォーカスを奪わない borderless パネル。1 ディスプレイに 1 枚。
final class FlamePanel: NSPanel {
    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: false)

        let view = FlameView(frame: NSRect(origin: .zero, size: screen.frame.size))
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 四辺に炎のパーティクルを描く view。Reduce Motion 時は静的なグロー枠に切り替える。
final class FlameView: NSView {
    private var emitterLayers: [CAEmitterLayer] = []
    private var staticGlowLayer: CALayer?
    private let flameDepth: CGFloat = 100
    private var intensity: Float = 1.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(frame: .zero)
        wantsLayer = true
        setup()
    }

    private func setup() {
        guard let rootLayer = layer else { return }
        rootLayer.frame = bounds
        rootLayer.masksToBounds = false

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            buildStaticGlow(in: rootLayer)
        } else {
            buildEmitters(in: rootLayer)
        }
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
        staticGlowLayer?.frame = bounds
        for emitter in emitterLayers {
            positionEmitter(emitter, in: bounds)
        }
    }

    /// 声量連動用の将来フック(今回は配線しない)。0〜1 で emitter の birthRate をスケールする。
    func setIntensity(_ level: Float) {
        intensity = max(0, min(1, level))
        for emitter in emitterLayers {
            guard let base = baseBirthRates[ObjectIdentifier(emitter)] else { continue }
            emitter.birthRate = base * intensity
        }
    }

    private var baseBirthRates: [ObjectIdentifier: Float] = [:]

    func stopEmitting() {
        for emitter in emitterLayers {
            emitter.birthRate = 0
        }
    }

    // MARK: - Static glow (Reduce Motion)

    private func buildStaticGlow(in rootLayer: CALayer) {
        let glow = CALayer()
        glow.frame = bounds
        glow.borderWidth = 24
        glow.borderColor = CGColor(red: 1, green: 0.35, blue: 0.05, alpha: 0.85)
        glow.shadowColor = CGColor(red: 1, green: 0.45, blue: 0.1, alpha: 1)
        glow.shadowOpacity = 0.9
        glow.shadowRadius = 40
        glow.shadowOffset = .zero
        rootLayer.addSublayer(glow)
        staticGlowLayer = glow
    }

    // MARK: - Emitters

    private enum Edge {
        case top, bottom, left, right
    }

    private func buildEmitters(in rootLayer: CALayer) {
        for edge in [Edge.top, .bottom, .left, .right] {
            let emitter = makeEmitter(for: edge)
            rootLayer.addSublayer(emitter)
            emitterLayers.append(emitter)
        }
    }

    private func positionEmitter(_ emitter: CAEmitterLayer, in bounds: CGRect) {
        guard let edge = edgeForEmitter(emitter) else { return }
        switch edge {
        case .top:
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY)
            emitter.emitterSize = CGSize(width: bounds.width, height: 4)
        case .bottom:
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY)
            emitter.emitterSize = CGSize(width: bounds.width, height: 4)
        case .left:
            emitter.emitterPosition = CGPoint(x: bounds.minX, y: bounds.midY)
            emitter.emitterSize = CGSize(width: 4, height: bounds.height)
        case .right:
            emitter.emitterPosition = CGPoint(x: bounds.maxX, y: bounds.midY)
            emitter.emitterSize = CGSize(width: 4, height: bounds.height)
        }
    }

    private var edgeTagKey: [ObjectIdentifier: Edge] = [:]

    private func edgeForEmitter(_ emitter: CAEmitterLayer) -> Edge? {
        edgeTagKey[ObjectIdentifier(emitter)]
    }

    /// AppKit の view は非フリップ座標(y は上向きに増える)。
    /// 下辺(y = minY)から出た炎は画面中央へ = 上向きに進む → yAcceleration は正。
    /// 上辺(y = maxY)から出た炎は中央へ = 下向きに進む → yAcceleration は負。
    /// 左辺は右向き(xAcceleration 正)、右辺は左向き(xAcceleration 負)。
    private func makeEmitter(for edge: Edge) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .rectangle
        emitter.renderMode = .additive

        let baseRate: Float
        switch edge {
        case .bottom: baseRate = 220
        case .top: baseRate = 100
        case .left, .right: baseRate = 160
        }

        let outerCell = makeCell(
            for: edge,
            color: CGColor(red: 1, green: 0.3, blue: 0.02, alpha: 1),
            redRange: 0.1, greenRange: 0.15, blueRange: 0.03,
            scale: 1.15, scaleRange: 0.4, scaleSpeed: -0.6,
            lifetime: 1.0, lifetimeRange: 0.3,
            birthRate: baseRate
        )
        let coreCell = makeCell(
            for: edge,
            color: CGColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
            redRange: 0.05, greenRange: 0.1, blueRange: 0.1,
            scale: 0.6, scaleRange: 0.2, scaleSpeed: -0.6,
            lifetime: 0.6, lifetimeRange: 0.2,
            birthRate: baseRate / 2
        )

        emitter.emitterCells = [outerCell, coreCell]
        emitter.birthRate = 1
        edgeTagKey[ObjectIdentifier(emitter)] = edge
        baseBirthRates[ObjectIdentifier(emitter)] = 1
        positionEmitter(emitter, in: bounds)
        return emitter
    }

    private func makeCell(
        for edge: Edge,
        color: CGColor,
        redRange: Float,
        greenRange: Float,
        blueRange: Float,
        scale: CGFloat,
        scaleRange: CGFloat,
        scaleSpeed: CGFloat,
        lifetime: Float,
        lifetimeRange: Float,
        birthRate: Float
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = Self.particleImage
        cell.lifetime = lifetime
        cell.lifetimeRange = lifetimeRange
        cell.scale = scale
        cell.scaleRange = scaleRange
        cell.scaleSpeed = scaleSpeed
        cell.alphaSpeed = -0.9
        cell.alphaRange = 0.15
        cell.color = color
        cell.redRange = redRange
        cell.greenRange = greenRange
        cell.blueRange = blueRange
        cell.emissionRange = 0.15
        cell.spin = 0
        cell.spinRange = 1.0
        cell.birthRate = birthRate

        switch edge {
        case .bottom:
            cell.velocity = 60
            cell.velocityRange = 20
            cell.yAcceleration = 90
            cell.emissionLongitude = .pi / 2
        case .top:
            cell.velocity = 60
            cell.velocityRange = 20
            cell.yAcceleration = -90
            cell.emissionLongitude = -.pi / 2
        case .left:
            cell.velocity = 60
            cell.velocityRange = 20
            cell.xAcceleration = 90
            cell.emissionLongitude = 0
        case .right:
            cell.velocity = 60
            cell.velocityRange = 20
            cell.xAcceleration = -90
            cell.emissionLongitude = .pi
        }

        return cell
    }

    // MARK: - Particle image

    private static let particleImage: CGImage = {
        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("failed to create flame particle context")
        }

        let colors: [CGFloat] = [
            1, 1, 1, 1,
            1, 1, 1, 0
        ]
        guard let gradient = CGGradient(
            colorSpace: colorSpace,
            colorComponents: colors,
            locations: [0, 1],
            count: 2
        ) else {
            fatalError("failed to create flame particle gradient")
        }

        let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: CGFloat(size) / 2,
            options: []
        )

        return context.makeImage()!
    }()
}
