import Foundation
import Combine

@MainActor
final class CompletionStore: ObservableObject {
    static let shared = CompletionStore()

    /// Interrupted Claude turns may never send Stop. Drop a working session
    /// after this long with no further event for that session.
    static let workingStateTimeout: TimeInterval = 15 * 60

    @Published private(set) var completions: [AgentEvent] = []
    @Published private(set) var workingSessions: [String: AgentEvent] = [:]

    var unreadCount: Int { completions.filter(\.unread).count }
    var isWorking: Bool { !workingSessions.isEmpty }

    /// Persisted history. Applied both when recording and when loading from disk.
    private let maxItems = 30
    /// Backstop so a burst of distinct session ids cannot grow without limit.
    private let maxWorkingSessions = 32
    private var workingTimeouts: [String: Task<Void, Never>] = [:]
    /// Only active sessions. A global counter avoids reusing a generation after cancel.
    private var timeoutGeneration: [String: Int] = [:]
    private var nextTimeoutGeneration = 0
    private let persistURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Doneko", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        persistURL = dir.appendingPathComponent("history.json")
        load()
    }

    /// Returns false when the event is a redundant reminder and should not alert.
    @discardableResult
    func handle(_ event: AgentEvent) -> Bool {
        switch event.kind {
        case .started:
            let key = sessionKey(for: event)
            workingSessions[key] = event
            scheduleWorkingTimeout(for: key)
            trimWorkingSessionsIfNeeded()
            return true
        case .completed, .needsAttention:
            // Claude's 60s idle reminder repeats a turn we already reported.
            if Self.isIdleReminder(event),
               let session = event.sessionID, !session.isEmpty,
               completions.contains(where: { $0.sessionID == session }) {
                return false
            }
            // Matching session leaves the working set, which stops the menu-bar animation.
            endWorking(for: event)
            var stored = event
            stored.unread = true
            if let session = event.sessionID, !session.isEmpty {
                // One row per session: keep only the newest.
                completions.removeAll { $0.sessionID == session }
            }
            completions.insert(stored, at: 0)
            if completions.count > maxItems {
                completions = Array(completions.prefix(maxItems))
            }
            save()
            return true
        }
    }

    static func isIdleReminder(_ event: AgentEvent) -> Bool {
        event.kind == .needsAttention
            && event.preview.localizedCaseInsensitiveContains("waiting for your input")
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

    private func sessionKey(for event: AgentEvent) -> String {
        if let session = event.sessionID, !session.isEmpty {
            return session
        }
        return event.id
    }

    /// Stop the working flag for this event. A completion without a session id
    /// cannot be paired (each event has its own id), so every working session
    /// from the same source is cleared — otherwise the icon would pulse until timeout.
    private func endWorking(for event: AgentEvent) {
        if let session = event.sessionID, !session.isEmpty {
            endWorkingSession(session)
            return
        }
        var keys: [String] = []
        for (key, value) in workingSessions where value.source == event.source {
            keys.append(key)
        }
        for key in keys {
            endWorkingSession(key)
        }
    }

    private func endWorkingSession(_ key: String) {
        cancelWorkingTimeout(for: key)
        guard workingSessions[key] != nil else { return }
        workingSessions.removeValue(forKey: key)
    }

    private func scheduleWorkingTimeout(for key: String) {
        nextTimeoutGeneration += 1
        let generation = nextTimeoutGeneration
        timeoutGeneration[key] = generation
        workingTimeouts[key]?.cancel()
        let nanos = UInt64(Self.workingStateTimeout * 1_000_000_000)
        workingTimeouts[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.expireWorkingSession(key, generation: generation)
        }
    }

    private func cancelWorkingTimeout(for key: String) {
        timeoutGeneration.removeValue(forKey: key)
        workingTimeouts[key]?.cancel()
        workingTimeouts.removeValue(forKey: key)
    }

    private func expireWorkingSession(_ key: String, generation: Int) {
        guard timeoutGeneration[key] == generation else { return }
        timeoutGeneration.removeValue(forKey: key)
        workingTimeouts.removeValue(forKey: key)
        workingSessions.removeValue(forKey: key)
    }

    private func trimWorkingSessionsIfNeeded() {
        guard workingSessions.count > maxWorkingSessions else { return }
        let overflow = workingSessions.count - maxWorkingSessions
        let oldest = workingSessions
            .sorted { $0.value.timestamp < $1.value.timestamp }
            .prefix(overflow)
            .map(\.key)
        for key in oldest {
            endWorkingSession(key)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([AgentEvent].self, from: data) else { return }
        var seen = Set<String>()
        let deduped = items.filter { item in
            if Self.isIdleReminder(item) { return false }
            guard let session = item.sessionID, !session.isEmpty else { return true }
            return seen.insert(session).inserted
        }
        let trimmed = deduped.count != items.count || deduped.count > maxItems
        completions = deduped.prefix(maxItems).map { item in
            var event = item
            event.unread = false
            return event
        }
        if trimmed {
            save()
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
