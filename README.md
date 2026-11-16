[English](README.md) · [简体中文](README.zh-CN.md)

# Doneko

> **done** + **neko** (Japanese for “cat”) — a macOS menu-bar paw that quietly tells you when Claude Code, Codex, or Antigravity CLI has finished answering.

- Event-driven, no polling; almost no CPU while idle
- Native Swift / SwiftUI / AppKit (not Electron)
- Requires macOS 13+
- The app UI is Simplified Chinese; the menu bar shows a cat paw

## Features

| Effect | What it does | Default |
| --- | --- | --- |
| System notification | Banner plus a system sound (soft **Purr** by default). Click to go back | On |
| Top capsule | Dynamic Island-style banner with the paw. Clickable | On |
| Edge glow | Full-screen click-through color wash (Claude leans orange / Codex leans blue / Antigravity leans green) | On |
| Menu-bar paw | Idle: monochrome template paw. Working: a light bounce. Unread: the whole paw turns orange (opening the menu, or reading everything, restores it) | On |
| Quiet in the foreground | No alert when the source terminal is already frontmost | On |
| Launch at login | Registered with `SMAppService` | Off |

Menu-bar history keeps only the newest row per session. The gray second line is the reply summary. Click a row to jump back to that terminal:

- **Ghostty** (recommended ≥ **1.4.0**): focus the exact terminal / tab by tty. With no tty, fall back to the working directory (several tabs in the same directory can land on the wrong one)
- **Terminal.app / iTerm2**: match tty / session id (iTerm uses the UUID after the colon in `ITERM_SESSION_ID`)
- Other terminals: activate the whole app from `TERM_PROGRAM`

Ghostty AppleScript support starts at **1.3.0**. Focusing by tty needs **≥ 1.4.0**. The first jump asks you, in System Settings → Privacy & Security → Automation, to let Doneko control Ghostty.

> There is no separate “meow” audio file (that would mean shipping copyrighted material). Use the system sounds **Purr**, **Glass**, and so on.

## Install

On a **Mac** (Xcode or the Command Line Tools already installed):

```bash
cd /path/to/Doneko
./install.sh
```

The script:

1. Runs `swift build -c release`
2. Assembles `~/Applications/Doneko.app` (`LSUIElement`, so no Dock icon; the Finder icon is an orange rounded paw) and ad-hoc signs it
3. Installs `~/.doneko/bin/doneko-notify`
4. Merges hooks into `~/.claude/settings.json` (backs up first, and removes legacy AgentPing hooks)
5. Merges Doneko’s handlers into `~/.codex/hooks.json` (`UserPromptSubmit` / `Stop` / `PermissionRequest`; other tools’ hooks stay). An existing `notify` line is **left alone** (only a `notify` line that an older Doneko wrote is removed, so hooks and `notify` do not alert twice). The first time, trust these hooks in Codex with `/hooks`
6. If Antigravity is installed (`~/.gemini` exists, or `agy` is on `PATH`), merges Doneko into `~/.gemini/config/hooks.json` (`PreInvocation` / `Stop`; other hooks stay). In `agy`, type `/hooks` to see them
7. Launches the app

## How to test

### In the app

Menu-bar paw → **设置…** (Settings…) → **测试 Claude Code** / **测试 Codex** / **测试 Antigravity**

### Call the script yourself

```bash
echo '{"session_id":"t1","cwd":"/tmp/demo","hook_event_name":"Stop","last_assistant_message":"搞定了"}' \
  | ~/.doneko/bin/doneko-notify --source=claude --kind=completed

~/.doneko/bin/doneko-notify --source=codex --kind=completed \
  '{"type":"agent-turn-complete","cwd":"/tmp/demo","last-assistant-message":"Build passed."}'

# Antigravity Stop: the script prints {"decision":"stop"} on stdout. DONEKO_DRY_RUN=1 parses and does not deliver.
printf '%s' '{"conversationId":"t1","workspacePaths":["/tmp/demo"],"fullyIdle":true,"terminationReason":"model_stop","lastUserInput":"hi","transcriptPath":"/tmp/missing.jsonl"}' \
  | DONEKO_DRY_RUN=1 ~/.doneko/bin/doneko-notify --source=antigravity --kind=completed
```

### A real agent

1. Confirm the paw is in the menu bar
2. Claude Code: ask something and wait until the answer finishes
3. Codex: after you ask, the paw goes into the working animation; you are notified when the answer finishes or a permission is requested (the hooks must already be trusted with `/hooks`)
4. Antigravity (`agy`): after you ask, the paw goes into the working animation, and you are notified when the answer finishes. In `agy`, type `/hooks` to see Doneko

## Uninstall

```bash
./uninstall.sh
```

This removes the app and the notify script, and removes entries that **Doneko and legacy AgentPing** wrote in Claude settings, Codex `hooks.json`, and Antigravity `~/.gemini/config/hooks.json`. An older Doneko `notify` line in `config.toml` is removed too. Any other `notify` line stays.

## Architecture

```
Claude Code hooks / Codex hooks / Antigravity hooks
        │
        ▼
 ~/.doneko/bin/doneko-notify   (deliver in the background, then exit 0)
        │
        ├─ Unix domain socket (preferred)
        │     ~/Library/Application Support/Doneko/doneko.sock
        ├─ open doneko://event?json=… (launches the app if it is not running)
        └─ osascript notification (last resort)
        │
        ▼
   Doneko.app (menu-bar paw)
```

### Claude Code

- `UserPromptSubmit` → `started` (the paw starts the working animation)
- `Stop` → `completed`
- `Notification` → `needsAttention`

stdin is Claude’s own JSON. If `stop_hook_active == true`, the script exits quietly.

### Codex CLI

The installer writes `~/.codex/hooks.json`. It does not take the single `notify` slot in `config.toml`. There is now a start event, so the menu-bar “working” animation follows the turn. Codex asks you to **trust** these new hooks once with `/hooks`.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.doneko/bin/doneko-notify --source=codex --kind=started"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.doneko/bin/doneko-notify --source=codex --kind=completed"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.doneko/bin/doneko-notify --source=codex --kind=needsAttention"
          }
        ]
      }
    ]
  }
}
```

- `UserPromptSubmit` → `started` (the paw starts the working animation)
- `Stop` → `completed`
- `PermissionRequest` → `needsAttention`

Codex passes the event JSON on stdin.

### Antigravity CLI

If `~/.gemini` exists or `agy` is on `PATH`, the installer writes Doneko into the global `~/.gemini/config/hooks.json` (shared by the CLI, the app, and the IDE). `PreInvocation` and `Stop` must be a flat handler list. Do not wrap them in a `matcher` / `hooks` group.

```json
{
  "doneko": {
    "enabled": true,
    "PreInvocation": [
      {
        "type": "command",
        "command": "~/.doneko/bin/doneko-notify --source=antigravity --kind=started",
        "timeout": 10
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "~/.doneko/bin/doneko-notify --source=antigravity --kind=completed",
        "timeout": 10
      }
    ]
  }
}
```

- `PreInvocation` → `started` (before each model call; the paw starts the working animation)
- `Stop` → `completed` (alerts only when `fullyIdle` is true; if background work is still running, skip and wait for the next Stop)

The Stop hook **must** print `{"decision":"stop"}` on stdout. `"continue"` makes the agent enter the loop again. Other hooks should exit quickly and print no decision.

The session id is `conversationId`. The working directory is `workspacePaths[0]`. The summary prefers the last model reply in `transcriptPath` (`content` of the last `PLANNER_RESPONSE`). If that is missing, it falls back to the literal string `任务完成`. If `terminationReason` is `error`, the summary is prefixed with the literal string `出错：`.

**Limit:** Antigravity has no “waiting for permission / needs input” hook, so Doneko does not raise a needs-attention alert for it. There is also no verified link that opens one existing conversation, so a click does not invent a URL and does not start a new chat.

Clicking the top capsule, the system notification, or a working / completed row in the menu:

- Antigravity App (`transcriptPath` under `~/.gemini/antigravity/`, or a parent process that is `Antigravity.app`) only activates `com.google.antigravity`
- Antigravity IDE only activates `com.google.antigravity-ide`
- `agy` in a real terminal (data directory `antigravity-cli`, and no GUI parent) still jumps by tty / terminal session
- If the origin cannot be confirmed, Doneko does not open some other installed terminal

An App / IDE parent process, and the data directory that holds the transcript, win over a `TERM_PROGRAM` the hook may have inherited. Quiet-in-the-foreground uses the same origin: the App or IDE is silenced only when that app itself is frontmost.

In `agy`, type `/hooks` to see the hooks that are loaded.

## First-run permissions

1. **Notifications** → Allow
2. **Automation** (jump back to Terminal / iTerm / **Ghostty**) → allow Doneko to control that terminal
3. Gatekeeper: right-click the app → Open

> Ghostty: upgrade to **≥ 1.4** for an exact tty jump. 1.3 only has AppleScript / working-directory matching. If Automation permission is denied, Doneko does not pretend the jump succeeded.

## Troubleshooting

| What you see | What to check |
| --- | --- |
| Nothing at all | The paw is in the menu bar; look at `~/.doneko/logs/notify.log` |
| A notification, but no capsule | Whether the capsule is turned off; whether **前台不打扰** is on (the setting is labeled **终端前台时不打扰**) |
| Claude never fires | `/hooks` lists Doneko; check `~/.claude/settings.json` |
| Codex never fires | `[features] hooks = true` in `~/.codex/config.toml`; trust Doneko with `/hooks` inside Codex |
| Antigravity never fires | `~/.gemini/config/hooks.json` contains `doneko`; in `agy`, type `/hooks` |
| The jump fails | System Settings → Privacy & Security → Automation → enable Doneko (including Ghostty) |
| Ghostty comes forward but does not switch tabs | Upgrade to Ghostty ≥ 1.4; confirm the hook captured a tty (event JSON / notify log) |
| Several Ghostty tabs in one directory, and the wrong tab is focused | Expected when there is no tty: the guess is by cwd. After tty capture works, the jump uses the tty |

```bash
ls -l ~/Library/Application\ Support/Doneko/doneko.sock
```

## Development

```bash
swift build -c release
# the binary is usually at .build/release/Doneko

# Regenerate the app icon (needs Pillow). On a Mac, install.sh uses iconutil to build the icns.
python3 Scripts/render-app-icon.py
```

Bundle ID: `com.yiming.doneko` · URL scheme: `doneko://` · MIT License

## License

MIT © 2026 YIMING YUAN
