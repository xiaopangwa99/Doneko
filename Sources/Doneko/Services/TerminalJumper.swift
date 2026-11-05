import AppKit
import Foundation

@MainActor
enum TerminalJumper {
    /// Jump back to the originating terminal tab/session when possible.
    /// - Parameters:
    ///   - terminal: Captured terminal identity from the notify hook.
    ///   - cwd: Event working directory; used as a Ghostty fallback (may be imprecise if several tabs share a cwd).
    static func jump(to terminal: TerminalInfo, cwd: String? = nil) {
        if isGhostty(terminal) {
            if jumpGhostty(tty: terminal.tty, cwd: cwd) { return }
            activateBundle("com.mitchellh.ghostty")
            return
        }

        if let iterm = terminal.itermSessionID, !iterm.isEmpty {
            if activateITerm(sessionID: iterm) { return }
        }
        if terminal.termProgram == "Apple_Terminal" || terminal.bundleID == "com.apple.Terminal" {
            if let tty = normalizeTTY(terminal.tty), activateTerminalApp(tty: tty) { return }
        }
        if let tty = normalizeTTY(terminal.tty), activateITermByTTY(tty: tty) { return }
        if let tty = normalizeTTY(terminal.tty), activateTerminalApp(tty: tty) { return }

        let bundle = terminal.bundleID
            ?? TerminalInfo.bundleID(forTermProgram: terminal.termProgram)
        if let bundle, activateBundle(bundle) { return }

        // Last resort: frontmost terminal-like app already running.
        for candidate in [
            "com.googlecode.iterm2",
            "com.apple.Terminal",
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
            "com.todesktop.230313mzl4w4u92",
            "com.microsoft.VSCode"
        ] {
            if activateBundle(candidate) { return }
        }
    }

    private static func isGhostty(_ terminal: TerminalInfo) -> Bool {
        if terminal.bundleID == "com.mitchellh.ghostty" { return true }
        if let program = terminal.termProgram?.lowercased(), program == "ghostty" { return true }
        return false
    }

    /// Normalize to `/dev/ttys…` / `/dev/pts/…` form Ghostty / Terminal expect.
    static func normalizeTTY(_ tty: String?) -> String? {
        guard var t = tty?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return nil
        }
        if t == "not a tty" || t == "?" || t == "??" || t == "-" { return nil }
        if t.hasPrefix("/dev/") { return t }
        if t.hasPrefix("tty") || t.hasPrefix("pts/") {
            return "/dev/" + t
        }
        return t
    }

    /// Ghostty ≥1.4: focus by tty. Fallback: working directory (imprecise). Final: activate app only.
    @discardableResult
    private static func jumpGhostty(tty: String?, cwd: String?) -> Bool {
        if let tty = normalizeTTY(tty), activateGhosttyByTTY(tty: tty) {
            return true
        }
        if let cwd, !cwd.isEmpty, activateGhosttyByCWD(cwd: cwd) {
            NSLog("Doneko: Ghostty 无 tty，已按工作目录跳转（同目录多 tab 可能不准）: \(cwd)")
            return true
        }
        return false
    }

    @discardableResult
    private static func activateGhosttyByTTY(tty: String) -> Bool {
        let escaped = escapeAppleScriptString(tty)
        let script = """
        tell application "Ghostty"
            set matches to every terminal whose tty is "\(escaped)"
            if (count of matches) > 0 then
                focus item 1 of matches
                return true
            end if
        end tell
        return false
        """
        return runAppleScript(script, context: "Ghostty tty=\(tty)")
    }

    @discardableResult
    private static func activateGhosttyByCWD(cwd: String) -> Bool {
        let escaped = escapeAppleScriptString(cwd)
        // Prefer exact working directory; Ghostty may omit trailing slash.
        let script = """
        tell application "Ghostty"
            set matches to every terminal whose working directory is "\(escaped)"
            if (count of matches) = 0 then
                set matches to every terminal whose working directory contains "\(escaped)"
            end if
            if (count of matches) > 0 then
                focus item 1 of matches
                return true
            end if
        end tell
        return false
        """
        return runAppleScript(script, context: "Ghostty cwd=\(cwd)")
    }

    @discardableResult
    private static func activateBundle(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                NSLog("Doneko: 激活 \(bundleID) 失败: \(error.localizedDescription)")
            }
        }
        return true
    }

    @discardableResult
    private static func activateTerminalApp(tty: String) -> Bool {
        let escaped = escapeAppleScriptString(tty)
        let script = """
        tell application "Terminal"
            activate
            set targetTTY to "\(escaped)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t is equal to targetTTY then
                            set selected of t to true
                            set index of w to 1
                            return true
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script, context: "Terminal.app tty")
    }

    /// ITERM_SESSION_ID is often `w0t0p0:UUID`. Prefer the UUID after the colon for `unique id`.
    @discardableResult
    private static func activateITerm(sessionID: String) -> Bool {
        let uuidPart: String = {
            if let idx = sessionID.firstIndex(of: ":") {
                let after = String(sessionID[sessionID.index(after: idx)...])
                if !after.isEmpty { return after }
            }
            return sessionID
        }()
        let candidates = Array(Set([uuidPart, sessionID])).filter { !$0.isEmpty }
        for candidate in candidates {
            if activateITermMatching(candidate) { return true }
        }
        return false
    }

    @discardableResult
    private static func activateITermMatching(_ sessionID: String) -> Bool {
        let escaped = escapeAppleScriptString(sessionID)
        let script = """
        tell application "iTerm"
            activate
            set targetID to "\(escaped)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if id of s is equal to targetID then
                                select t
                                select s
                                set index of w to 1
                                return true
                            end if
                        end try
                        try
                            if unique id of s is equal to targetID then
                                select t
                                select s
                                set index of w to 1
                                return true
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script, context: "iTerm session")
    }

    @discardableResult
    private static func activateITermByTTY(tty: String) -> Bool {
        let escaped = escapeAppleScriptString(tty)
        let script = """
        tell application "iTerm"
            activate
            set targetTTY to "\(escaped)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if tty of s is equal to targetTTY then
                                select t
                                select s
                                set index of w to 1
                                return true
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return runAppleScript(script, context: "iTerm tty")
    }

    private static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    private static func runAppleScript(_ source: String, context: String = "") -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            NSLog("Doneko: 无法创建 AppleScript\(context.isEmpty ? "" : " (\(context))")")
            return false
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            // -1743 = not authorized (Automation permission)
            if code == -1743 {
                NSLog("Doneko: 需要「自动化」权限才能跳回终端（\(context)）。请在 系统设置 → 隐私与安全性 → 自动化 中允许 Doneko 控制 Ghostty / Terminal / iTerm，然后重试。未假装跳转成功。")
            } else {
                NSLog("Doneko: AppleScript 失败\(context.isEmpty ? "" : " (\(context))" ): [\(code)] \(message)")
            }
            return false
        }
        if result.booleanValue { return true }
        if result.stringValue == "true" { return true }
        return false
    }

    /// Whether the originating terminal appears to be the frontmost app.
    static func isOriginFrontmost(_ terminal: TerminalInfo) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        let expected = terminal.bundleID
            ?? TerminalInfo.bundleID(forTermProgram: terminal.termProgram)
        if let expected, front == expected { return true }
        let terminals: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
            "com.todesktop.230313mzl4w4u92",
            "com.microsoft.VSCode",
            "co.zeit.hyper",
            "org.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm"
        ]
        if expected == nil, terminals.contains(front) { return true }
        return false
    }
}
