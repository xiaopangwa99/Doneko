import AppKit
import QuartzCore

@MainActor
final class EdgeGlowController {
    private var windows: [NSWindow] = []

    func flash(source: AgentSource, duration: CFTimeInterval = 1.5) {
        clear()
        let rgb = source.glowRGB
        let color = NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 0.85)

        for screen in NSScreen.screens {
            let win = makeWindow(for: screen, color: color)
            windows.append(win)
            win.orderFrontRegardless()
            animate(window: win, duration: duration)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in
            self?.clear()
        }
    }

    private func clear() {
        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll()
    }

    private func makeWindow(for screen: NSScreen, color: NSColor) -> NSWindow {
        let frame = screen.frame
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        win.hidesOnDeactivate = false

        let view = GlowView(frame: NSRect(origin: .zero, size: frame.size), glowColor: color)
        win.contentView = view
        win.alphaValue = 0
        return win
    }

    private func animate(window: NSWindow, duration: CFTimeInterval) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration * 0.35
            window.animator().alphaValue = 1
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration * 0.65
                window.animator().alphaValue = 0
            }
        })
    }
}

private final class GlowView: NSView {
    let glowColor: NSColor
    private let borderWidth: CGFloat = 28

    init(frame: NSRect, glowColor: NSColor) {
        self.glowColor = glowColor
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        rebuildLayers()
    }

    private func rebuildLayers() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let layer else { return }

        let b = bounds
        let w = borderWidth

        func addEdge(rect: CGRect, start: CGPoint, end: CGPoint) {
            let edge = CAGradientLayer()
            edge.frame = rect
            edge.colors = [
                glowColor.withAlphaComponent(0.55).cgColor,
                glowColor.withAlphaComponent(0.0).cgColor
            ]
            edge.startPoint = start
            edge.endPoint = end
            layer.addSublayer(edge)
        }

        // Top / Bottom / Left / Right soft gradients inward.
        addEdge(rect: CGRect(x: 0, y: b.height - w, width: b.width, height: w),
                start: CGPoint(x: 0.5, y: 1), end: CGPoint(x: 0.5, y: 0))
        addEdge(rect: CGRect(x: 0, y: 0, width: b.width, height: w),
                start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        addEdge(rect: CGRect(x: 0, y: 0, width: w, height: b.height),
                start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
        addEdge(rect: CGRect(x: b.width - w, y: 0, width: w, height: b.height),
                start: CGPoint(x: 1, y: 0.5), end: CGPoint(x: 0, y: 0.5))
    }
}
