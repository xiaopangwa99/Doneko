import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class CapsuleController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(event: AgentEvent, duration: Double, onClick: @escaping () -> Void) {
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel = nil

        let width: CGFloat = 360
        let height: CGFloat = 64

        let hosting = NSHostingView(rootView: CapsuleView(event: event))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = ClickablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hosting
        panel.onClick = onClick

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        // Place just below the menu bar / notch area, centered.
        let x = visible.midX - width / 2
        let topY = screen.frame.maxY - (screen.frame.maxY - visible.maxY) - 8
        let startFrame = NSRect(x: x, y: topY + 12, width: width, height: height)
        let endFrame = NSRect(x: x, y: topY - height, width: width, height: height)

        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1.5, duration), execute: work)
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
            var f = panel.frame
            f.origin.y += 16
            panel.animator().setFrame(f, display: true)
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            if self?.panel === panel {
                self?.panel = nil
            }
        })
    }
}

private final class ClickablePanel: NSPanel {
    var onClick: (() -> Void)?

    override var canBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        orderOut(nil)
    }
}

private struct CapsuleView: View {
    let event: AgentEvent

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.25))
                    .frame(width: 36, height: 36)
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(event.projectName + (event.preview.isEmpty ? "" : " · " + event.preview))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .padding(2)
    }

    private var title: String {
        switch event.kind {
        case .completed: return event.source.answeredTitle
        case .needsAttention: return event.source.needsAttentionTitle
        case .started: return event.source.workingTitle
        }
    }

    private var iconName: String {
        CatIcon.capsuleSymbolName(for: event.kind)
    }

    private var accent: Color {
        let rgb = event.source.glowRGB
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}
