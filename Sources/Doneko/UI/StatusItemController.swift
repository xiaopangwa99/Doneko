import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var animationTimer: Timer?
    private var pulsePhase: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.baseImage(unread: false, working: false, phase: 0)
            button.imagePosition = .imageOnly
            button.toolTip = "Doneko — agent 完成提醒"
        }
        statusItem = item
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
        let working = store.isWorking && AppSettings.shared.enableMenuBarAnimation
        let unread = store.unreadCount > 0

        if working {
            startAnimation()
        } else {
            stopAnimation()
            statusItem?.button?.image = Self.baseImage(unread: unread, working: false, phase: 0)
        }

        if let button = statusItem?.button {
            button.toolTip = working
                ? "Agent 工作中…"
                : (unread ? "有 \(store.unreadCount) 条未读回答 🐱" : "Doneko — 空闲")
        }
        rebuildMenu()
    }

    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pulsePhase += 0.18
                let unread = CompletionStore.shared.unreadCount > 0
                self.statusItem?.button?.image = Self.baseImage(
                    unread: unread,
                    working: true,
                    phase: self.pulsePhase
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        pulsePhase = 0
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

        self.statusItem?.menu = menu
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

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func baseImage(unread: Bool, working: Bool, phase: CGFloat) -> NSImage {
        CatIcon.menuBarImage(unread: unread, working: working, phase: phase)
    }
}
