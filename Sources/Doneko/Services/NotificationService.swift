import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let terminalCategoryID = "DONEKO_COMPLETE"
    private let appCategoryID = "DONEKO_OPEN_APP"
    private let jumpActionID = "JUMP"

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let jump = UNNotificationAction(
            identifier: jumpActionID,
            title: "跳回终端",
            options: [.foreground]
        )
        let openApp = UNNotificationAction(
            identifier: jumpActionID,
            title: "打开 Antigravity",
            options: [.foreground]
        )
        let terminalCategory = UNNotificationCategory(
            identifier: terminalCategoryID,
            actions: [jump],
            intentIdentifiers: [],
            options: []
        )
        let appCategory = UNNotificationCategory(
            identifier: appCategoryID,
            actions: [openApp],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([terminalCategory, appCategory])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("Doneko: 通知权限错误: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Doneko: 用户未授予通知权限")
            }
        }
    }

    func post(event: AgentEvent, soundName: String) {
        let content = UNMutableNotificationContent()
        switch event.kind {
        case .completed:
            content.title = event.source.answeredTitle
        case .needsAttention:
            content.title = event.source.needsAttentionTitle
        case .started:
            return
        }
        content.subtitle = event.projectName
        let host = event.terminal.host
        if event.preview.isEmpty {
            content.body = host.applicationBundleID == nil ? "点击跳回对应终端" : "点击打开 Antigravity"
        } else {
            content.body = event.preview
        }
        // Bundle may not contain system sounds; use default banner sound + NSSound.
        content.sound = .default
        content.categoryIdentifier = host.applicationBundleID == nil
            ? terminalCategoryID
            : appCategoryID
        content.userInfo = [
            "eventID": event.id,
            "cwd": event.cwd,
            "tty": event.terminal.tty ?? "",
            "termProgram": event.terminal.termProgram ?? "",
            "termSessionID": event.terminal.termSessionID ?? "",
            "itermSessionID": event.terminal.itermSessionID ?? "",
            "ghosttySurfaceID": event.terminal.ghosttySurfaceID ?? "",
            "bundleID": event.terminal.bundleID ?? "",
            "host": host.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: event.id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Doneko: 发送通知失败: \(error.localizedDescription)")
            }
        }

        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            let hostRaw = (info["host"] as? String) ?? ""
            let terminal = TerminalInfo(
                termProgram: info["termProgram"] as? String,
                termSessionID: info["termSessionID"] as? String,
                itermSessionID: info["itermSessionID"] as? String,
                ghosttySurfaceID: info["ghosttySurfaceID"] as? String,
                tty: info["tty"] as? String,
                parentPID: nil,
                bundleID: info["bundleID"] as? String,
                host: OriginHost(rawValue: hostRaw) ?? .unknown
            )
            if let id = info["eventID"] as? String {
                CompletionStore.shared.markRead(id)
            }
            let cwd = info["cwd"] as? String
            TerminalJumper.jump(to: terminal, cwd: cwd)
            completionHandler()
        }
    }
}
