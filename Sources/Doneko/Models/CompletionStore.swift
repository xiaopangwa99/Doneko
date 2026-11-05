import Foundation
import Combine

@MainActor
final class CompletionStore: ObservableObject {
    static let shared = CompletionStore()

    @Published private(set) var completions: [AgentEvent] = []
    @Published private(set) var workingSessions: [String: AgentEvent] = [:]

    var unreadCount: Int { completions.filter(\.unread).count }
    var isWorking: Bool { !workingSessions.isEmpty }

    private let maxItems = 30
    private let persistURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Doneko", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        persistURL = dir.appendingPathComponent("history.json")
        load()
    }

    func handle(_ event: AgentEvent) {
        switch event.kind {
        case .started:
            let key = event.sessionID ?? event.id
            workingSessions[key] = event
        case .completed, .needsAttention:
            let key = event.sessionID ?? event.id
            workingSessions.removeValue(forKey: key)
            var stored = event
            stored.unread = true
            completions.insert(stored, at: 0)
            if completions.count > maxItems {
                completions = Array(completions.prefix(maxItems))
            }
            save()
        }
    }

    func markRead(_ id: String) {
        guard let idx = completions.firstIndex(where: { $0.id == id }) else { return }
        completions[idx].unread = false
        save()
    }

    func markAllRead() {
        for i in completions.indices {
            completions[i].unread = false
        }
        save()
    }

    func clear() {
        completions = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let items = try? decoder.decode([AgentEvent].self, from: data) {
            completions = items.map { var e = $0; e.unread = false; return e }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(completions) {
            try? data.write(to: persistURL, options: .atomic)
        }
    }
}
