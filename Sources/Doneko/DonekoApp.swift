import SwiftUI
import AppKit

@main
struct DonekoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // LSUIElement menu-bar app: no regular window scene required.
        Settings {
            SettingsView()
                .frame(minWidth: 420, minHeight: 480)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationService.shared.configure()
        EventRouter.shared.start()
        statusItem.setup()

        // Sync login-item toggle with actual SMAppService state.
        let actual = LoginItemManager.shared.isEnabled
        if AppSettings.shared.launchAtLogin != actual {
            AppSettings.shared.launchAtLogin = actual
        }

        NSLog("Doneko: 已启动，监听 \(SocketServer.shared.socketPath)")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SocketServer.shared.stop()
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "doneko" else { return }
        // doneko://event?<url-encoded-json>  or  doneko://jump?id=...
        if url.host == "event" || url.path == "/event" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let json = components.queryItems?.first(where: { $0.name == "json" })?.value,
               let data = json.data(using: .utf8) {
                EventRouter.shared.ingest(data: data)
            }
        } else if url.host == "jump" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
               let event = CompletionStore.shared.completions.first(where: { $0.id == id }) {
                CompletionStore.shared.markRead(id)
                TerminalJumper.jump(to: event.terminal, cwd: event.cwd)
            }
        }
    }
}
