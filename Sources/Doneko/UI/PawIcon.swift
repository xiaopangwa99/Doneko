import AppKit
import SwiftUI

/// Cat paw used by the menu bar (template / orange) and the capsule.
/// Proportions match `Scripts/render-app-icon.py`.
enum PawIcon {
    struct Toe {
        var cx: CGFloat
        var cy: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    /// Unit box, y up. Toes are tall ovals; the main pad is a smooth bean.
    static let toes: [Toe] = [
        Toe(cx: 0.40, cy: 0.705, width: 0.145, height: 0.210),
        Toe(cx: 0.60, cy: 0.705, width: 0.145, height: 0.210),
        Toe(cx: 0.23, cy: 0.545, width: 0.130, height: 0.175),
        Toe(cx: 0.77, cy: 0.545, width: 0.130, height: 0.175)
    ]

    static let pad: [CGPoint] = [
        CGPoint(x: 0.500, y: 0.500),
        CGPoint(x: 0.620, y: 0.485),
        CGPoint(x: 0.720, y: 0.425),
        CGPoint(x: 0.765, y: 0.345),
        CGPoint(x: 0.700, y: 0.255),
        CGPoint(x: 0.580, y: 0.215),
        CGPoint(x: 0.500, y: 0.205),
        CGPoint(x: 0.420, y: 0.215),
        CGPoint(x: 0.300, y: 0.255),
        CGPoint(x: 0.235, y: 0.345),
        CGPoint(x: 0.280, y: 0.425),
        CGPoint(x: 0.380, y: 0.485)
    ]

    static func menuBarImage(unread: Bool, working: Bool, phase: CGFloat) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let alpha: CGFloat
            let bounce: CGFloat
            if working {
                let wave = 0.5 + 0.5 * sin(phase)
                alpha = 0.62 + 0.38 * wave
                bounce = sin(phase) * 0.9
            } else {
                alpha = 1
                bounce = 0
            }
            let color = unread
                ? NSColor.systemOrange.withAlphaComponent(alpha)
                : NSColor.black.withAlphaComponent(alpha)
            color.setFill()
            let rect = NSRect(x: 1.5, y: 1.2 + bounce, width: 15, height: 15)
            bezier(in: rect).fill()
            return true
        }
        image.isTemplate = !unread
        image.cacheMode = .always
        return image
    }

    static func bezier(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        for oval in ovals(in: rect) {
            path.appendOval(in: oval)
        }
        let outline = scaledPad(in: rect)
        if let first = outline.first {
            path.move(to: first)
            for point in outline.dropFirst() {
                path.line(to: point)
            }
            path.close()
        }
        return path
    }

    static func ovals(in rect: CGRect) -> [CGRect] {
        toes.map { toe in
            let width = toe.width * rect.width
            let height = toe.height * rect.height
            let cx = rect.minX + toe.cx * rect.width
            let cy = rect.minY + toe.cy * rect.height
            return CGRect(x: cx - width / 2, y: cy - height / 2, width: width, height: height)
        }
    }

    static func scaledPad(in rect: CGRect) -> [CGPoint] {
        catmullRom(pad).map { point in
            CGPoint(
                x: rect.minX + point.x * rect.width,
                y: rect.minY + point.y * rect.height
            )
        }
    }

    private static func catmullRom(_ points: [CGPoint], samples: Int = 10) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        var result: [CGPoint] = []
        result.reserveCapacity(points.count * samples)
        let count = points.count
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = points[(index + 2) % count]
            for step in 0..<samples {
                let t = CGFloat(step) / CGFloat(samples)
                let t2 = t * t
                let t3 = t2 * t
                let x = 0.5 * (
                    (2 * p1.x)
                        + (-p0.x + p2.x) * t
                        + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                        + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3
                )
                let y = 0.5 * (
                    (2 * p1.y)
                        + (-p0.y + p2.y) * t
                        + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                        + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3
                )
                result.append(CGPoint(x: x, y: y))
            }
        }
        return result
    }
}

struct PawShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for oval in PawIcon.ovals(in: rect) {
            path.addEllipse(in: oval)
        }
        let outline = PawIcon.scaledPad(in: rect)
        if let first = outline.first {
            path.move(to: first)
            for point in outline.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        return path
    }
}
