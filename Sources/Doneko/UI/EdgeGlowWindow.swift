import AppKit
import QuartzCore

/// Full-screen edge glow shown only for the duration of a flash.
/// Windows are created on demand and closed afterwards — nothing stays ordered in,
/// and the fade is removed so a hidden window is not left animating.
@MainActor
final class EdgeGlowController {
    private var windows: [NSWindow] = []
    private var dismissWork: DispatchWorkItem?
    private var generation = 0

    func flash(source: AgentSource, duration: CFTimeInterval = 1.5) {
        generation += 1
        let token = generation
        releaseWindows()

        let rgb = source.glowRGB
        let color = NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 0.85)

        for screen in NSScreen.screens {
            let win = makeWindow(for: screen, color: color)
            windows.append(win)
            win.contentView?.layoutSubtreeIfNeeded()
            // Alpha is 0 until the fade starts, so ordering front does not flash.
            win.orderFrontRegardless()
            animate(window: win, duration: duration, token: token)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.releaseWindows()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1, execute: work)
    }

    private func releaseWindows() {
        dismissWork?.cancel()
        dismissWork = nil
        // Drop windows before stopping the fade so a completion handler cannot
        // start the second half on a window that is being closed.
        let existing = windows
        windows.removeAll()
        for win in existing {
            win.contentView?.layer?.removeAllAnimations()
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            win.animator().alphaValue = 0
            NSAnimationContext.endGrouping()
            win.orderOut(nil)
            win.contentView = nil
            win.close()
        }
    }

    private func makeWindow(for screen: NSScreen, color: NSColor) -> NSWindow {
        let frame = screen.frame
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true,
            screen: screen
        )
        // ARC owns the window via `windows` until releaseWindows() drops it.
        win.isReleasedWhenClosed = false
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

    private func animate(window: NSWindow, duration: CFTimeInterval, token: Int) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration * 0.35
            window.animator().alphaValue = 1
        }, completionHandler: { [weak self, weak window] in
            guard let self, let window else { return }
            guard self.generation == token else { return }
            guard self.windows.contains(where: { $0 === window }) else { return }
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
    private var lastLayoutSize: CGSize = .zero

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
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
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
