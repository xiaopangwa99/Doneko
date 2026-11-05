import Foundation
import AppKit

enum AgentSource: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .unknown: return "Agent"
        }
    }

    var answeredTitle: String {
        switch self {
        case .claude: return "Claude Code 已回答"
        case .codex: return "Codex 已回答"
        case .unknown: return "Agent 已回答"
        }
    }

    var workingTitle: String {
        switch self {
        case .claude: return "Claude Code 工作中"
        case .codex: return "Codex 工作中"
        case .unknown: return "Agent 工作中"
        }
    }

    var needsAttentionTitle: String {
        switch self {
        case .claude: return "Claude Code 需要关注"
        case .codex: return "Codex 需要关注"
        case .unknown: return "Agent 需要关注"
        }
    }

    /// Soft glow / accent color (sRGB 0–1).
    var glowRGB: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .claude: return (0.85, 0.45, 0.25)
        case .codex: return (0.25, 0.65, 0.95)
        case .unknown: return (0.55, 0.55, 0.60)
        }
    }
}

enum AgentEventKind: String, Codable {
    case started
    case completed
    case needsAttention
}

struct TerminalInfo: Codable, Equatable {
    var termProgram: String?
    var termSessionID: String?
    var itermSessionID: String?
    /// Ghostty ≥1.4 surface id from `GHOSTTY_SURFACE_ID` (optional; tty focus is primary).
    var ghosttySurfaceID: String?
    var tty: String?
    var parentPID: Int?
    var bundleID: String?

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
