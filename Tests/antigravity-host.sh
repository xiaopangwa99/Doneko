#!/usr/bin/env bash
# Isolated host-routing checks for doneko-notify. Does not install hooks,
# touch a real home directory, or deliver socket / history events.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/Scripts/doneko-notify"
BASE="$(mktemp -d /tmp/doneko-host.XXXXXX)"
export HOME="$BASE/home"
export DONEKO_SOCK="$BASE/missing.sock"
export DONEKO_DRY_RUN=1
mkdir -p "$HOME"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'PASS %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; printf '  %s\n' "$2" >&2; }

APP_TRANSCRIPT="$HOME/.gemini/antigravity/brain/conv/.system_generated/logs/transcript.jsonl"
CLI_TRANSCRIPT="$HOME/.gemini/antigravity-cli/brain/conv/.system_generated/logs/transcript.jsonl"
IDE_TRANSCRIPT="$HOME/.gemini/antigravity-ide/brain/conv/.system_generated/logs/transcript.jsonl"

# tty, ancestors, and TERM_PROGRAM are explicit so this machine's process tree
# cannot leak into the classification.
run() {
  local payload="$1" tty="$2" ancestors="$3" term="$4"
  shift 4
  local out="$BASE/out" err="$BASE/err"
  : >"$out"
  : >"$err"
  set +e
  printf '%s' "$payload" | \
    HOME="$HOME" \
    DONEKO_SOCK="$DONEKO_SOCK" \
    DONEKO_DRY_RUN=1 \
    TERM_PROGRAM="$term" \
    TERM_SESSION_ID= \
    ITERM_SESSION_ID= \
    GHOSTTY_SURFACE_ID= \
    DONEKO_TTY="$tty" \
    DONEKO_ANCESTORS="$ancestors" \
    "$SCRIPT" "$@" >"$out" 2>"$err"
  RC=$?
  set -e
  STDOUT="$(cat "$out")"
  STDERR="$(cat "$err")"
}

host_of() {
  python3 -c 'import json,sys; print(json.loads(sys.argv[1])["terminal"]["host"])' "$1"
}
field_of() {
  python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$1" "$2"
}
term_of() {
  python3 -c 'import json,sys; v=json.loads(sys.argv[1])["terminal"].get(sys.argv[2]); print("" if v is None else v)' "$1" "$2"
}

stop_payload() {
  local transcript="$1"
  printf '%s' "{\"conversationId\":\"conv-1\",\"workspacePaths\":[\"/work/htl-order-xproduction-service\"],\"transcriptPath\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$transcript"),\"lastUserInput\":\"ship the fix\",\"fullyIdle\":true,\"terminationReason\":\"model_stop\",\"error\":\"\"}"
}

assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then ok "$name"; else bad "$name" "got=$(printf %q "$got") want=$(printf %q "$want")"; fi
}

# App transcript wins over an inherited Ghostty environment.
run "$(stop_payload "$APP_TRANSCRIPT")" /dev/ttys004 $'/bin/zsh\n' ghostty \
  --source=antigravity --kind=completed
assert_eq "app host beats inherited ghostty" "$(host_of "$STDERR")" "antigravity-app"
assert_eq "app still records inherited tty" "$(term_of "$STDERR" tty)" "/dev/ttys004"
assert_eq "app cwd is the workspace" "$(field_of "$STDERR" cwd)" "/work/htl-order-xproduction-service"
assert_eq "app project name" "$(field_of "$STDERR" projectName)" "htl-order-xproduction-service"
assert_eq "app stop decision" "$STDOUT" '{"decision":"stop"}'
assert_eq "app stop exit" "$RC" "0"
[[ "$STDOUT" != *continue* ]] && ok "app stop is not continue" || bad "app stop is not continue" "$STDOUT"

# IDE transcript, same inherited terminal.
run "$(stop_payload "$IDE_TRANSCRIPT")" /dev/ttys004 '' ghostty \
  --source=antigravity --kind=completed
assert_eq "ide host" "$(host_of "$STDERR")" "antigravity-ide"
assert_eq "ide stop decision" "$STDOUT" '{"decision":"stop"}'

# CLI transcript keeps a real terminal session.
run "$(stop_payload "$CLI_TRANSCRIPT")" /dev/ttys009 $'/bin/zsh\n' ghostty \
  --source=antigravity --kind=completed
assert_eq "cli host" "$(host_of "$STDERR")" "terminal"
assert_eq "cli tty preserved" "$(term_of "$STDERR" tty)" "/dev/ttys009"
assert_eq "cli term program" "$(term_of "$STDERR" termProgram)" "ghostty"
assert_eq "cli bundle" "$(term_of "$STDERR" bundleID)" "com.mitchellh.ghostty"
assert_eq "cli stop decision" "$STDOUT" '{"decision":"stop"}'

# Tilde path uses the same directory components.
run "$(stop_payload "~/.gemini/antigravity/brain/conv/.system_generated/logs/transcript.jsonl")" /dev/ttys001 '' iTerm.app \
  --source=antigravity --kind=completed
assert_eq "tilde app host" "$(host_of "$STDERR")" "antigravity-app"

# GUI ancestry beats a CLI transcript path and inherited terminal env.
run "$(stop_payload "$CLI_TRANSCRIPT")" /dev/ttys004 $'/Applications/Antigravity.app/Contents/MacOS/Antigravity\n' ghostty \
  --source=antigravity --kind=completed
assert_eq "app ancestry beats cli transcript" "$(host_of "$STDERR")" "antigravity-app"

run "$(stop_payload "$APP_TRANSCRIPT")" /dev/ttys004 $'/Applications/Antigravity IDE.app/Contents/MacOS/Antigravity IDE\n' ghostty \
  --source=antigravity --kind=completed
assert_eq "ide ancestry beats app transcript" "$(host_of "$STDERR")" "antigravity-ide"

# Bundle ids: the IDE id contains the app id as a prefix.
run "$(stop_payload "")" '' $'helper com.google.antigravity-ide\n' '' \
  --source=antigravity --kind=completed
assert_eq "ide bundle ancestry is not the app" "$(host_of "$STDERR")" "antigravity-ide"

run "$(stop_payload "")" '' $'helper com.google.antigravity\n' '' \
  --source=antigravity --kind=completed
assert_eq "app bundle ancestry" "$(host_of "$STDERR")" "antigravity-app"

# No GUI evidence and no terminal identity: unknown. A workspace named
# antigravity must not count.
UNKNOWN='{"conversationId":"c","workspacePaths":["/work/antigravity"],"fullyIdle":true,"terminationReason":"model_stop","error":""}'
run "$UNKNOWN" '' '' '' --source=antigravity --kind=completed
assert_eq "unknown without evidence" "$(host_of "$STDERR")" "unknown"
assert_eq "unknown project is not a host signal" "$(field_of "$STDERR" projectName)" "antigravity"
assert_eq "unknown still stops" "$STDOUT" '{"decision":"stop"}'

# A real tty with no GUI evidence is a terminal session (agy without a transcript).
run "$UNKNOWN" /dev/ttys003 '' Apple_Terminal --source=antigravity --kind=completed
assert_eq "tty without gui evidence is terminal" "$(host_of "$STDERR")" "terminal"

# PreInvocation has no fullyIdle / terminationReason. It records the host and
# prints no stop decision.
PRE="$(python3 -c 'import json,sys; print(json.dumps({"invocationNum":1,"conversationId":"conv-1","workspacePaths":["/work/htl-order-xproduction-service"],"transcriptPath":sys.argv[1],"lastUserInput":"ship the fix"}))' "$APP_TRANSCRIPT")"
run "$PRE" /dev/ttys004 '' ghostty --source=antigravity --kind=started
assert_eq "started host" "$(host_of "$STDERR")" "antigravity-app"
assert_eq "started kind" "$(field_of "$STDERR" kind)" "started"
assert_eq "started prints no decision" "$STDOUT" ""

# fullyIdle false still prints stop and suppresses the event.
BUSY='{"conversationId":"c","workspacePaths":["/work/htl-order-xproduction-service"],"transcriptPath":"'"$APP_TRANSCRIPT"'","fullyIdle":false,"terminationReason":"model_stop","error":""}'
run "$BUSY" /dev/ttys004 '' ghostty --source=antigravity --kind=completed
assert_eq "nonidle stop decision" "$STDOUT" '{"decision":"stop"}'
assert_eq "nonidle no event" "$STDERR" ""
assert_eq "nonidle exit" "$RC" "0"

# Claude / Codex stay on the terminal host and do not print a stop decision.
run '{"session_id":"t1","cwd":"/tmp/demo","hook_event_name":"Stop","last_assistant_message":"ok"}' \
  /dev/ttys002 '' '' --source=claude --kind=completed
assert_eq "claude host" "$(host_of "$STDERR")" "terminal"
assert_eq "claude stdout empty" "$STDOUT" ""
assert_eq "claude source" "$(field_of "$STDERR" source)" "claude"

run "" '' '' '' --source=codex --kind=completed \
  '{"type":"agent-turn-complete","cwd":"/tmp/demo","last-assistant-message":"Build passed."}'
assert_eq "codex host" "$(host_of "$STDERR")" "terminal"
assert_eq "codex stdout empty" "$STDOUT" ""
assert_eq "codex preview" "$(field_of "$STDERR" preview)" "Build passed."

# Notification userInfo round-trip for a GUI event and a CLI event.
# Keys match NotificationService.post / didReceive.
run "$(stop_payload "$APP_TRANSCRIPT")" /dev/ttys004 '' ghostty \
  --source=antigravity --kind=completed
cp "$BASE/err" "$BASE/app-event.json"
run "$(stop_payload "$CLI_TRANSCRIPT")" /dev/ttys009 '' ghostty \
  --source=antigravity --kind=completed
cp "$BASE/err" "$BASE/cli-event.json"
python3 - "$BASE/app-event.json" "$BASE/cli-event.json" << 'PY'
import json, sys

def user_info(event):
    term = event["terminal"]
    return {
        "eventID": event["id"],
        "cwd": event["cwd"],
        "tty": term.get("tty") or "",
        "termProgram": term.get("termProgram") or "",
        "termSessionID": term.get("termSessionID") or "",
        "itermSessionID": term.get("itermSessionID") or "",
        "ghosttySurfaceID": term.get("ghosttySurfaceID") or "",
        "bundleID": term.get("bundleID") or "",
        "host": term.get("host") or "",
    }

def restored_host(info):
    # NotificationService: OriginHost(rawValue:) ?? .unknown, empty string included.
    raw = info.get("host") or ""
    return raw if raw in ("terminal", "antigravity-app", "antigravity-ide", "unknown") else "unknown"

app = json.loads(open(sys.argv[1], encoding="utf-8").read())
cli = json.loads(open(sys.argv[2], encoding="utf-8").read())
app_info = user_info(app)
cli_info = user_info(cli)
assert restored_host(app_info) == "antigravity-app"
assert app_info["tty"] == "/dev/ttys004"  # inherited tty is stored, host still wins in the jumper
assert app_info["cwd"].endswith("htl-order-xproduction-service")
assert restored_host(cli_info) == "terminal"
assert cli_info["tty"] == "/dev/ttys009"
legacy = dict(app_info)
del legacy["host"]
assert restored_host(legacy) == "unknown"
blob = json.dumps(app_info) + json.dumps(cli_info)
assert "antigravity://" not in blob and "antigravity-ide://" not in blob
print("notify-userinfo-roundtrip-ok")
PY

# Old history has no host key. The Swift decoder must default it.
python3 - << 'PY'
import json
old = {
    "id": "old",
    "kind": "completed",
    "source": "antigravity",
    "cwd": "/work/htl-order-xproduction-service",
    "projectName": "htl-order-xproduction-service",
    "preview": "done",
    "sessionID": "conv-old",
    "timestamp": "2026-11-01T00:00:00Z",
    "terminal": {
        "termProgram": "ghostty",
        "tty": "/dev/ttys004",
        "bundleID": "com.mitchellh.ghostty",
    },
    "unread": False,
}
assert "host" not in old["terminal"]
# Same rule as TerminalInfo.init(from:): missing host becomes unknown.
restored = old["terminal"].get("host") or "unknown"
assert restored == "unknown"
print("old-history-missing-host-ok")
PY

swift_jumper="$ROOT/Sources/Doneko/Services/TerminalJumper.swift"
swift_model="$ROOT/Sources/Doneko/Models/AgentEvent.swift"
swift_note="$ROOT/Sources/Doneko/Services/NotificationService.swift"
grep -q 'applicationBundleID' "$swift_jumper" && ok "jumper consults host bundle before terminal jump" || bad "jumper host check" ""
grep -q 'allowInstalledFallback: terminal.host == .terminal' "$swift_jumper" && ok "installed-terminal fallback only for confirmed terminal host" || bad "fallback guard" ""
grep -q 'decodeIfPresent(OriginHost.self, forKey: .host) ?? .unknown' "$swift_model" && ok "old history decodes missing host as unknown" || bad "decode default" ""
grep -q '"host": host.rawValue' "$swift_note" && ok "notification stores host" || bad "notification store" ""
grep -q 'OriginHost(rawValue: hostRaw) ?? .unknown' "$swift_note" && ok "notification restores host" || bad "notification restore" ""
if grep -R -n -E 'antigravity://|antigravity-ide://' "$ROOT/Sources" "$ROOT/Scripts" >/dev/null; then
  bad "invented url scheme" "$(grep -R -n -E 'antigravity://|antigravity-ide://' "$ROOT/Sources" "$ROOT/Scripts")"
else
  ok "no conversation url scheme"
fi

# Real account paths stay absent.
for p in /home/ubuntu/.gemini /home/ubuntu/.codex /home/ubuntu/.doneko "/home/ubuntu/Library/Application Support/Doneko"; do
  if [[ -e "$p" ]]; then bad "real path created: $p" ""; else ok "real path absent: $p"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
exit "$fail"
