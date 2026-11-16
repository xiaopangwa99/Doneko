import Foundation
import AppKit

enum AgentSource: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case antigravity
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        case .unknown: return "Agent"
        }
    }

    var answeredTitle: String {
        switch self {
        case .claude: return "Claude Code 已回答"
        case .codex: return "Codex 已回答"
        case .antigravity: return "Antigravity 已回答"
        case .unknown: return "Agent 已回答"
        }
    }

    var workingTitle: String {
        switch self {
        case .claude: return "Claude Code 工作中"
        case .codex: return "Codex 工作中"
        case .antigravity: return "Antigravity 工作中"
        case .unknown: return "Agent 工作中"
        }
    }

    var needsAttentionTitle: String {
        switch self {
        case .claude: return "Claude Code 需要关注"
        case .codex: return "Codex 需要关注"
        case .antigravity: return "Antigravity 需要关注"
        case .unknown: return "Agent 需要关注"
        }
    }

    /// Soft glow / accent color (sRGB 0–1).
    var glowRGB: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .claude: return (0.85, 0.45, 0.25)
        case .codex: return (0.25, 0.65, 0.95)
        case .antigravity: return (0.20, 0.75, 0.55)
        case .unknown: return (0.55, 0.55, 0.60)
        }
    }
}

enum AgentEventKind: String, Codable {
    case started
    case completed
    case needsAttention
}

/// Where a click should go. Missing on history written before this field existed.
enum OriginHost: String, Codable, Equatable {
    case terminal
    case antigravityApp = "antigravity-app"
    case antigravityIDE = "antigravity-ide"
    case unknown

    /// Graphical client to activate. Terminal sessions and unknown hosts have none.
    var applicationBundleID: String? {
        switch self {
        case .antigravityApp:
            return "com.google.antigravity"
        case .antigravityIDE:
            return "com.google.antigravity-ide"
        case .terminal, .unknown:
            return nil
        }
    }
}

struct TerminalInfo: Equatable {
    var termProgram: String?
    var termSessionID: String?
    var itermSessionID: String?
    /// Ghostty ≥1.4 surface id from `GHOSTTY_SURFACE_ID` (optional; tty focus is primary).
    var ghosttySurfaceID: String?
    var tty: String?
    var parentPID: Int?
    var bundleID: String?
    /// `unknown` when an older history row did not record a host.
    var host: OriginHost = .unknown

    static func captureFromEnvironment(
        ttyOverride: String? = nil,
        parentPIDOverride: Int? = nil
    ) -> TerminalInfo {
        let env = ProcessInfo.processInfo.environment
        let termProgram = env["TERM_PROGRAM"]
        return TerminalInfo(
            termProgram: termProgram,
            termSessionID: env["TERM_SESSION_ID"],
            itermSessionID: env["ITERM_SESSION_ID"],
            ghosttySurfaceID: env["GHOSTTY_SURFACE_ID"],
            tty: ttyOverride ?? env["DONEKO_TTY"] ?? Self.guessTTY(),
            parentPID: parentPIDOverride ?? Int(env["DONEKO_PPID"] ?? "") ?? Int(getppid()),
            bundleID: Self.bundleID(forTermProgram: termProgram)
        )
    }

    private static func guessTTY() -> String? {
        if let name = ttyname(STDIN_FILENO) {
            return String(cString: name)
        }
        if let name = ttyname(STDOUT_FILENO) {
            return String(cString: name)
        }
        return nil
    }

    static func bundleID(forTermProgram program: String?) -> String? {
        guard let program else { return nil }
        switch program {
        case "Apple_Terminal":
            return "com.apple.Terminal"
        case "iTerm.app":
            return "com.googlecode.iterm2"
        case "ghostty":
            return "com.mitchellh.ghostty"
        case "WarpTerminal":
            return "dev.warp.Warp-Stable"
        case "vscode":
            if NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.todesktop.230313mzl4w4u92"
            ) != nil {
                return "com.todesktop.230313mzl4w4u92"
            }
            return "com.microsoft.VSCode"
        case "cursor":
            return "com.todesktop.230313mzl4w4u92"
        case "Hyper":
            return "co.zeit.hyper"
        case "Alacritty":
            return "org.alacritty"
        case "kitty":
            return "net.kovidgoyal.kitty"
        case "WezTerm":
            return "com.github.wez.wezterm"
        default:
            return nil
        }
    }
}

extension TerminalInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case termProgram, termSessionID, itermSessionID, ghosttySurfaceID
        case tty, parentPID, bundleID, host
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        termProgram = try container.decodeIfPresent(String.self, forKey: .termProgram)
        termSessionID = try container.decodeIfPresent(String.self, forKey: .termSessionID)
        itermSessionID = try container.decodeIfPresent(String.self, forKey: .itermSessionID)
        ghosttySurfaceID = try container.decodeIfPresent(String.self, forKey: .ghosttySurfaceID)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        parentPID = try container.decodeIfPresent(Int.self, forKey: .parentPID)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        // History and notifications from before host existed keep loading.
        host = try container.decodeIfPresent(OriginHost.self, forKey: .host) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(termProgram, forKey: .termProgram)
        try container.encodeIfPresent(termSessionID, forKey: .termSessionID)
        try container.encodeIfPresent(itermSessionID, forKey: .itermSessionID)
        try container.encodeIfPresent(ghosttySurfaceID, forKey: .ghosttySurfaceID)
        try container.encodeIfPresent(tty, forKey: .tty)
        try container.encodeIfPresent(parentPID, forKey: .parentPID)
        try container.encodeIfPresent(bundleID, forKey: .bundleID)
        try container.encode(host, forKey: .host)
    }
}

struct AgentEvent: Codable, Identifiable, Equatable {
    var id: String
    var kind: AgentEventKind
    var source: AgentSource
    var cwd: String
    var projectName: String
    var preview: String
    var sessionID: String?
    var timestamp: Date
    var terminal: TerminalInfo
    var unread: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, kind, source, cwd, projectName, preview, sessionID, timestamp, terminal, unread
    }

    static func projectName(from cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "项目" : name
    }

    static func truncate(_ text: String, limit: Int = 120) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= limit { return collapsed }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<idx]) + "…"
    }
}
