import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class CapsuleController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Bumped when a panel is dismissed, so a stale hide cannot release a newer
    /// panel or keep animating one that is already gone.
    private var generation = 0
    private var releasing: Set<ObjectIdentifier> = []

    func show(event: AgentEvent, duration: Double, onClick: @escaping () -> Void) {
        dismissImmediately()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let width: CGFloat = 360
        let height: CGFloat = 64
        let token = generation

        let hosting = NSHostingView(rootView: CapsuleView(event: event))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = ClickablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hosting
        panel.onClick = { [weak self] in
            onClick()
            guard let self, self.generation == token else { return }
            self.dismissImmediately()
        }

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
            guard let self, self.generation == token else { return }
            self.hide(token: token)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1.5, duration), execute: work)
    }

    private func hide(token: Int) {
        guard token == generation, let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
            var frame = panel.frame
            frame.origin.y += 16
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self, weak panel] in
            guard let self, let panel else { return }
            guard self.generation == token else { return }
            guard !self.releasing.contains(ObjectIdentifier(panel)) else { return }
            self.destroy(panel)
        })
    }

    /// Order out, stop in-flight animations, and drop the panel so it can deallocate.
    private func dismissImmediately() {
        generation += 1
        hideWork?.cancel()
        hideWork = nil
        guard let panel else { return }
        destroy(panel)
    }

    private func destroy(_ panel: NSPanel) {
        let id = ObjectIdentifier(panel)
        guard releasing.insert(id).inserted else { return }
        defer { releasing.remove(id) }
        // Invalidate the hide completion so it cannot run destroy again after
        // the zero-duration animation below finishes.
        generation += 1

        (panel as? ClickablePanel)?.onClick = nil
        panel.contentView?.layer?.removeAllAnimations()
        // Replace any in-flight window animation with a zero-duration one so it
        // does not keep running after the panel is ordered out. The releasing
        // set ignores the synchronous completion re-entry this can cause.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        panel.animator().alphaValue = 0
        NSAnimationContext.endGrouping()

        if self.panel === panel {
            self.panel = nil
        }
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }
}

private final class ClickablePanel: NSPanel {
    var onClick: (() -> Void)?

    override var canBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // Defer so the panel is not closed inside the mouse-down dispatch.
        let click = onClick
        DispatchQueue.main.async {
            click?()
        }
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
                PawShape()
                    .fill(accent)
                    .frame(width: 22, height: 22)
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

    private var accent: Color {
        let rgb = event.source.glowRGB
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}
