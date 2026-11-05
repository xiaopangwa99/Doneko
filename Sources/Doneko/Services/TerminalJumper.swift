import AppKit
import Foundation

@MainActor
enum TerminalJumper {
    static func jump(to terminal: TerminalInfo) {
        if let iterm = terminal.itermSessionID, !iterm.isEmpty {
            if activateITerm(sessionID: iterm) { return }
        }
        if terminal.termProgram == "Apple_Terminal" || terminal.bundleID == "com.apple.Terminal" {
            if let tty = terminal.tty, activateTerminalApp(tty: tty) { return }
        }
        if let tty = terminal.tty, activateITermByTTY(tty: tty) { return }
        if let tty = terminal.tty, activateTerminalApp(tty: tty) { return }

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
        let escaped = tty
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
        return runAppleScript(script)
    }

    @discardableResult
    private static func activateITerm(sessionID: String) -> Bool {
        let escaped = sessionID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // iTerm2 session id format varies; try matching id property.
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
        return runAppleScript(script)
    }

    @discardableResult
    private static func activateITermByTTY(tty: String) -> Bool {
        let escaped = tty
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
        return runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                // -1743 = not authorized (Automation permission)
                if code == -1743 {
                    NSLog("Doneko: 需要「自动化」权限才能跳回终端，请在 系统设置 → 隐私与安全性 → 自动化 中允许 Doneko。")
                } else {
                    NSLog("Doneko: AppleScript 错误: \(error)")
                }
                return false
            }
            if result.booleanValue { return true }
            // Some scripts return string "true"
            if result.stringValue == "true" { return true }
            return result.booleanValue
        }
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
        // Heuristic: any known terminal is frontmost and we have no better match.
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
