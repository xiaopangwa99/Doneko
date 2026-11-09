import Foundation
import AppKit

@MainActor
final class EventRouter {
    static let shared = EventRouter()

    private let capsule = CapsuleController()
    private let glow = EdgeGlowController()
    private var distributedObserver: NSObjectProtocol?

    func start() {
        SocketServer.shared.start { data in
            Task { @MainActor in
                EventRouter.shared.ingest(data: data)
            }
        }

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.yiming.doneko.event"),
            object: nil,
            queue: .main
        ) { note in
            guard let json = note.userInfo?["json"] as? String,
                  let data = json.data(using: .utf8) else { return }
            Task { @MainActor in
                EventRouter.shared.ingest(data: data)
            }
        }
    }

    func ingest(data: Data) {
        do {
            let event = try decodeEvent(from: data)
            process(event)
        } catch {
            NSLog("Doneko: 无法解析事件: \(error.localizedDescription)")
        }
    }

    func process(_ event: AgentEvent) {
        guard CompletionStore.shared.handle(event) else { return }

        switch event.kind {
        case .started:
            break
        case .completed, .needsAttention:
            deliverAlerts(for: event)
        }
    }

    func deliverAlerts(for event: AgentEvent, force: Bool = false) {
        let settings = AppSettings.shared

        if !force && settings.suppressWhenFocused && TerminalJumper.isOriginFrontmost(event.terminal) {
            return
        }

        if settings.enableSystemNotification {
            NotificationService.shared.post(event: event, soundName: settings.notificationSound)
        }
        if settings.enableCapsule {
            capsule.show(event: event, duration: settings.capsuleDuration) {
                CompletionStore.shared.markRead(event.id)
                TerminalJumper.jump(to: event.terminal, cwd: event.cwd)
            }
        }
        if settings.enableEdgeGlow {
            glow.flash(source: event.source)
        }
    }

    func testAlert(source: AgentSource) {
        let event = AgentEvent(
            id: UUID().uuidString,
            kind: .completed,
            source: source,
            cwd: FileManager.default.currentDirectoryPath,
            projectName: "测试项目",
            preview: "这是一条测试提醒，用于预览通知、胶囊与边缘柔光效果。",
            sessionID: "test",
            timestamp: Date(),
            terminal: TerminalInfo(
                termProgram: ProcessInfo.processInfo.environment["TERM_PROGRAM"],
                termSessionID: nil,
                itermSessionID: nil,
                ghosttySurfaceID: ProcessInfo.processInfo.environment["GHOSTTY_SURFACE_ID"],
                tty: nil,
                parentPID: nil,
                bundleID: nil
            ),
            unread: true
        )
        deliverAlerts(for: event, force: true)
        CompletionStore.shared.handle(event)
    }

    private func decodeEvent(from data: Data) throws -> AgentEvent {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let kind = obj["kind"] as? String,
           ["started", "completed", "needsAttention"].contains(kind) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AgentEvent.self, from: data)
        }

        let sourceRaw = (obj["source"] as? String) ?? "unknown"
        let source = AgentSource(rawValue: sourceRaw) ?? .unknown
        let kindRaw = (obj["kind"] as? String) ?? "completed"
        let kind = AgentEventKind(rawValue: kindRaw) ?? .completed
        let cwd = (obj["cwd"] as? String) ?? FileManager.default.currentDirectoryPath
        let preview = AgentEvent.truncate((obj["preview"] as? String) ?? "")
        let session = obj["session_id"] as? String ?? obj["sessionID"] as? String
        let termProgram = obj["term_program"] as? String
        let nested = obj["terminal"] as? [String: Any]
        let term = TerminalInfo(
            termProgram: termProgram ?? nested?["termProgram"] as? String,
            termSessionID: obj["term_session_id"] as? String ?? nested?["termSessionID"] as? String,
            itermSessionID: obj["iterm_session_id"] as? String ?? nested?["itermSessionID"] as? String,
            ghosttySurfaceID: nested?["ghosttySurfaceID"] as? String ?? obj["ghostty_surface_id"] as? String,
            tty: obj["tty"] as? String ?? nested?["tty"] as? String,
            parentPID: obj["ppid"] as? Int ?? nested?["parentPID"] as? Int,
            bundleID: TerminalInfo.bundleID(forTermProgram: termProgram ?? nested?["termProgram"] as? String)
                ?? nested?["bundleID"] as? String
        )
        return AgentEvent(
            id: (obj["id"] as? String) ?? UUID().uuidString,
            kind: kind,
            source: source,
            cwd: cwd,
            projectName: AgentEvent.projectName(from: cwd),
            preview: preview,
            sessionID: session,
            timestamp: Date(),
            terminal: term,
            unread: true
        )
    }
}
