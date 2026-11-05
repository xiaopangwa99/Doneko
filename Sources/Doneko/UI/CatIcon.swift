import AppKit

enum CatIcon {
    /// Menu-bar sized cat. Prefers SF Symbol `cat` / `cat.fill` on macOS 14+;
    /// falls back to a hand-drawn template Bézier cat for macOS 13.
    static func menuBarImage(unread: Bool, working: Bool, phase: CGFloat) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            var alpha: CGFloat = 1
            if working {
                alpha = 0.55 + 0.45 * (0.5 + 0.5 * sin(phase))
            }

            let drewSymbol: Bool
            if #available(macOS 14.0, *) {
                let symbolName = working ? "cat.fill" : "cat"
                if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Doneko") {
                    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                    let configured = symbol.withSymbolConfiguration(config)
                    configured?.draw(
                        in: NSRect(x: 1, y: 1, width: 16, height: 16),
                        from: .zero,
                        operation: .sourceOver,
                        fraction: alpha
                    )
                    drewSymbol = true
                } else {
                    drewSymbol = false
                }
            } else {
                drewSymbol = false
            }

            if !drewSymbol {
                drawBezierCat(
                    in: NSRect(x: 1, y: 1, width: 16, height: 16),
                    alpha: alpha,
                    working: working,
                    phase: phase
                )
            }

            if unread {
                let dot = NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 6, height: 6))
                NSColor.systemOrange.setFill()
                dot.fill()
                NSColor.white.withAlphaComponent(0.9).setStroke()
                dot.lineWidth = 0.8
                dot.stroke()
            }
            return true
        }
        image.isTemplate = !unread
        return image
    }

    /// Simple cat head + ears (+ optional ear bob when working).
    static func drawBezierCat(in rect: NSRect, alpha: CGFloat, working: Bool, phase: CGFloat) {
        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }

        let color = NSColor.labelColor.withAlphaComponent(alpha)
        color.setStroke()
        color.setFill()

        let w = rect.width
        let h = rect.height
        let ox = rect.origin.x
        let oy = rect.origin.y

        let head = NSBezierPath(ovalIn: NSRect(
            x: ox + w * 0.18,
            y: oy + h * 0.08,
            width: w * 0.64,
            height: h * 0.62
        ))
        head.lineWidth = 1.2
        head.stroke()

        let earBob: CGFloat = working ? CGFloat(sin(Double(phase) * 1.4)) * (h * 0.04) : 0

        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: ox + w * 0.28, y: oy + h * 0.55))
        leftEar.line(to: NSPoint(x: ox + w * 0.22, y: oy + h * 0.92 + earBob))
        leftEar.line(to: NSPoint(x: ox + w * 0.42, y: oy + h * 0.62))
        leftEar.close()
        leftEar.lineWidth = 1.1
        leftEar.stroke()

        let rightEar = NSBezierPath()
        rightEar.move(to: NSPoint(x: ox + w * 0.72, y: oy + h * 0.55))
        rightEar.line(to: NSPoint(x: ox + w * 0.78, y: oy + h * 0.92 - earBob))
        rightEar.line(to: NSPoint(x: ox + w * 0.58, y: oy + h * 0.62))
        rightEar.close()
        rightEar.lineWidth = 1.1
        rightEar.stroke()

        let eyeY = oy + h * 0.38
        NSBezierPath(ovalIn: NSRect(x: ox + w * 0.34, y: eyeY, width: w * 0.10, height: h * 0.12)).fill()
        NSBezierPath(ovalIn: NSRect(x: ox + w * 0.56, y: eyeY, width: w * 0.10, height: h * 0.12)).fill()

        let nose = NSBezierPath()
        nose.move(to: NSPoint(x: ox + w * 0.50, y: oy + h * 0.28))
        nose.line(to: NSPoint(x: ox + w * 0.45, y: oy + h * 0.22))
        nose.line(to: NSPoint(x: ox + w * 0.55, y: oy + h * 0.22))
        nose.close()
        nose.fill()

        let whisker = NSBezierPath()
        whisker.move(to: NSPoint(x: ox + w * 0.30, y: oy + h * 0.26))
        whisker.line(to: NSPoint(x: ox + w * 0.08, y: oy + h * 0.30))
        whisker.move(to: NSPoint(x: ox + w * 0.30, y: oy + h * 0.22))
        whisker.line(to: NSPoint(x: ox + w * 0.08, y: oy + h * 0.18))
        whisker.move(to: NSPoint(x: ox + w * 0.70, y: oy + h * 0.26))
        whisker.line(to: NSPoint(x: ox + w * 0.92, y: oy + h * 0.30))
        whisker.move(to: NSPoint(x: ox + w * 0.70, y: oy + h * 0.22))
        whisker.line(to: NSPoint(x: ox + w * 0.92, y: oy + h * 0.18))
        whisker.lineWidth = 0.8
        whisker.stroke()
    }

    static func capsuleSymbolName(for kind: AgentEventKind) -> String {
        if #available(macOS 14.0, *) {
            switch kind {
            case .completed: return "cat.fill"
            case .needsAttention: return "exclamationmark.bubble.fill"
            case .started: return "cat"
            }
        }
        switch kind {
        case .completed: return "checkmark.circle.fill"
        case .needsAttention: return "exclamationmark.bubble.fill"
        case .started: return "ellipsis.circle.fill"
        }
    }
}
