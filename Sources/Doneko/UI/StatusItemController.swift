import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// ~3 Hz bounce. Eight cached paw frames; a status item only accepts an NSImage.
    private static let animationInterval: TimeInterval = 1.0 / 3.0
    private static let animationTolerance: TimeInterval = 0.1
    private static let animationFrameCount = 8

    private struct IconKey: Hashable {
        var unread: Bool
        var working: Bool
        var frame: Int
        var appearance: String
    }

    private var statusItem: NSStatusItem?
    private var animationTimer: Timer?
    private var animationGeneration = 0
    private var frameIndex = 0
    private var iconCache: [IconKey: NSImage] = [:]
    /// Orange paw until the menu is opened or every item is read.
    private var iconAcknowledged = true
    private var seenUnreadCount = 0
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = icon(unread: false, working: false)
            button.imagePosition = .imageOnly
            button.toolTip = "Doneko — agent 完成提醒"
        }
        rebuildMenu()

        CompletionStore.shared.$completions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        CompletionStore.shared.$workingSessions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        AppSettings.shared.$enableMenuBarAnimation
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        let store = CompletionStore.shared
        // isWorking drops on completed/needsAttention and on workingStateTimeout.
        let working = store.isWorking && AppSettings.shared.enableMenuBarAnimation
        let unread = iconShowsUnread()

        if working {
            startAnimationIfNeeded()
            statusItem?.button?.image = icon(unread: unread, working: true)
        } else {
            stopAnimation()
            statusItem?.button?.image = icon(unread: unread, working: false)
        }

        if let button = statusItem?.button {
            button.toolTip = working
                ? "Agent 工作中…"
                : (store.unreadCount > 0 ? "有 \(store.unreadCount) 条未读" : "Doneko — 空闲")
        }
        rebuildMenu()
    }

    private func startAnimationIfNeeded() {
        guard animationTimer == nil else { return }
        frameIndex = 0
        prewarmWorkingFrames()
        let generation = animationGeneration
        let timer = Timer(timeInterval: Self.animationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.animationGeneration == generation else { return }
                self.tickAnimation()
            }
        }
        timer.tolerance = Self.animationTolerance
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        guard animationTimer != nil else { return }
        // Bump first so a tick already queued cannot paint a working frame afterwards.
        animationGeneration += 1
        animationTimer?.invalidate()
        animationTimer = nil
        frameIndex = 0
    }

    private func tickAnimation() {
        let store = CompletionStore.shared
        guard store.isWorking, AppSettings.shared.enableMenuBarAnimation else {
            stopAnimation()
            statusItem?.button?.image = icon(unread: iconShowsUnread(), working: false)
            return
        }
        frameIndex = (frameIndex + 1) % Self.animationFrameCount
        statusItem?.button?.image = icon(unread: iconShowsUnread(), working: true)
    }

    /// Whole paw turns orange while something is unread. Opening the menu, or
    /// reading the last item, puts the template paw back.
    private func iconShowsUnread() -> Bool {
        let count = CompletionStore.shared.unreadCount
        if count > seenUnreadCount {
            iconAcknowledged = false
        } else if count == 0 {
            iconAcknowledged = true
        }
        seenUnreadCount = count
        return count > 0 && !iconAcknowledged
    }

    private func acknowledgeUnreadIcon() {
        guard !iconAcknowledged else { return }
        iconAcknowledged = true
        let working = CompletionStore.shared.isWorking && AppSettings.shared.enableMenuBarAnimation
        statusItem?.button?.image = icon(unread: false, working: working)
    }

    private func prewarmWorkingFrames() {
        let appearance = appearanceKey()
        for unread in [false, true] {
            for frame in 0..<Self.animationFrameCount {
                _ = cachedIcon(unread: unread, working: true, frame: frame, appearance: appearance)
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let store = CompletionStore.shared

        let statusTitle: String
        if store.isWorking {
            statusTitle = "状态：工作中（\(store.workingSessions.count)）"
        } else if store.unreadCount > 0 {
            statusTitle = "状态：有 \(store.unreadCount) 条未读"
        } else {
            statusTitle = "状态：空闲"
        }
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        if store.completions.isEmpty {
            let empty = NSMenuItem(title: "暂无最近完成记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for event in store.completions.prefix(12) {
                let time = Self.timeString(event.timestamp)
                let mark = event.unread ? "● " : "○ "
                let title = "\(mark)\(event.source.displayName) · \(event.projectName) · \(time)"
                let item = NSMenuItem(
                    title: title,
                    action: #selector(openCompletion(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = event.id
                item.toolTip = event.preview
                item.attributedTitle = Self.menuTitle(head: title, summary: event.preview)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let markAll = NSMenuItem(title: "全部标为已读", action: #selector(markAllRead), keyEquivalent: "")
        markAll.target = self
        markAll.isEnabled = store.unreadCount > 0
        menu.addItem(markAll)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Doneko", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        self.statusItem?.menu = menu
    }

    @objc func menuWillOpen(_ menu: NSMenu) {
        acknowledgeUnreadIcon()
    }

    @objc private func openCompletion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let event = CompletionStore.shared.completions.first(where: { $0.id == id }) else { return }
        CompletionStore.shared.markRead(id)
        TerminalJumper.jump(to: event.terminal, cwd: event.cwd)
        refresh()
    }

    @objc private func markAllRead() {
        CompletionStore.shared.markAllRead()
        refresh()
    }

    @objc private func openSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Doneko 设置"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        SocketServer.shared.stop()
        NSApp.terminate(nil)
    }

    private static func menuTitle(head: String, summary: String) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: head,
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )
        let cleaned = summary
            .replacingOccurrences(of: "[*`#>]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return text }
        let limit = 36
        let short = cleaned.count > limit ? String(cleaned.prefix(limit)) + "…" : cleaned
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 0
        text.append(NSAttributedString(
            string: "\n    " + short,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]
        ))
        return text
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func icon(unread: Bool, working: Bool) -> NSImage {
        let frame = working ? frameIndex : 0
        return cachedIcon(
            unread: unread,
            working: working,
            frame: frame,
            appearance: appearanceKey()
        )
    }

    private func cachedIcon(unread: Bool, working: Bool, frame: Int, appearance: String) -> NSImage {
        let key = IconKey(unread: unread, working: working, frame: frame, appearance: appearance)
        if let cached = iconCache[key] {
            return cached
        }
        if iconCache.count > 64 {
            iconCache.removeAll(keepingCapacity: true)
        }
        let phase = working ? pulsePhase(for: frame) : 0
        let image = PawIcon.menuBarImage(unread: unread, working: working, phase: phase)
        iconCache[key] = image
        return image
    }

    private func pulsePhase(for frame: Int) -> CGFloat {
        CGFloat(frame) / CGFloat(Self.animationFrameCount) * (2 * CGFloat.pi)
    }

    private func appearanceKey() -> String {
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        if let match = appearance.bestMatch(from: [.aqua, .darkAqua]) {
            return match.rawValue
        }
        return appearance.name.rawValue
    }
}
