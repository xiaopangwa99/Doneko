#!/usr/bin/env bash
# Doneko installer — build, bundle, codesign, install hooks
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Doneko"
BUNDLE_ID="com.yiming.doneko"
APP_DIR="${HOME}/Applications/${APP_NAME}.app"
SUPPORT_BIN="${HOME}/.doneko/bin"
NOTIFY_DST="${SUPPORT_BIN}/doneko-notify"
BUILD_DIR="${ROOT}/.build"
RELEASE_BIN="${BUILD_DIR}/release/${APP_NAME}"

echo "==> Doneko 安装程序（done + neko）"
echo "    源码: ${ROOT}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "错误: 请在 macOS 上运行此安装脚本（当前是 $(uname -s)）。" >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "错误: 未找到 swift。请先安装 Xcode 或 Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

echo "==> 编译 release（swift build -c release）…"
cd "${ROOT}"
swift build -c release

if [[ ! -x "${RELEASE_BIN}" ]]; then
  # SPM may nest under arch triple
  RELEASE_BIN="$(find "${BUILD_DIR}/release" -maxdepth 3 -type f -name Doneko -perm -111 | head -n1 || true)"
fi
if [[ -z "${RELEASE_BIN}" || ! -x "${RELEASE_BIN}" ]]; then
  echo "错误: 找不到编译产物 Doneko" >&2
  exit 1
fi
echo "    二进制: ${RELEASE_BIN}"

echo "==> 组装 ${APP_NAME}.app…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${RELEASE_BIN}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

ICONSET="${ROOT}/Resources/AppIcon.iconset"
ICNS="${ROOT}/Resources/AppIcon.icns"
echo "==> 安装 App 图标…"
if [[ -d "${ICONSET}" ]] && command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns" \
    || cp "${ICNS}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
elif [[ -f "${ICNS}" ]]; then
  cp "${ICNS}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi
if [[ ! -f "${APP_DIR}/Contents/Resources/AppIcon.icns" ]]; then
  echo "警告: 未找到 AppIcon.iconset / AppIcon.icns，Finder 会显示占位图标。" >&2
fi

# Minimal PkgInfo
echo -n 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "==> 临时签名（ad-hoc）…"
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || {
  echo "警告: codesign 失败，继续安装（首次打开可能需右键 → 打开）。"
}

echo "==> 安装 hook 脚本 → ${NOTIFY_DST}"
mkdir -p "${SUPPORT_BIN}"
cp "${ROOT}/Scripts/doneko-notify" "${NOTIFY_DST}"
chmod +x "${NOTIFY_DST}"

# ---------- Claude Code settings.json merge ----------
CLAUDE_DIR="${HOME}/.claude"
CLAUDE_SETTINGS="${CLAUDE_DIR}/settings.json"
mkdir -p "${CLAUDE_DIR}"

echo "==> 合并 Claude Code hooks → ${CLAUDE_SETTINGS}"
if [[ -f "${CLAUDE_SETTINGS}" ]]; then
  cp "${CLAUDE_SETTINGS}" "${CLAUDE_SETTINGS}.doneko.bak.$(date +%Y%m%d%H%M%S)"
  echo "    已备份现有 settings.json"
fi

NOTIFY_ESC="${NOTIFY_DST}"
/usr/bin/python3 - "${CLAUDE_SETTINGS}" "${NOTIFY_ESC}" <<'PY'
import json, os, sys, time

path, notify = sys.argv[1], sys.argv[2]
data = {}
if os.path.isfile(path):
    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except Exception:
            data = {}

if not isinstance(data, dict):
    data = {}

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, list) and not isinstance(hooks, dict):
    hooks = {}
    data["hooks"] = hooks

MARKERS = ("doneko-notify", "agentping-notify")

def is_ours(handler):
    if not isinstance(handler, dict):
        return False
    cmd = handler.get("command") or ""
    args = handler.get("args") or []
    blob = cmd + " " + " ".join(args if isinstance(args, list) else [])
    return any(m in blob for m in MARKERS)

def ensure_event(event_name, kind):
    groups = hooks.get(event_name)
    if not isinstance(groups, list):
        groups = []
    # Remove previous Doneko handlers, keep others
    new_groups = []
    for g in groups:
        if not isinstance(g, dict):
            new_groups.append(g)
            continue
        handlers = g.get("hooks") or []
        kept = [h for h in handlers if not is_ours(h)]
        if kept:
            ng = dict(g)
            ng["hooks"] = kept
            new_groups.append(ng)
        elif not handlers:
            new_groups.append(g)
    # Append our handler group
    our = {
        "hooks": [
            {
                "type": "command",
                "command": notify,
                "args": [f"--source=claude", f"--kind={kind}"],
                "timeout": 5,
                "async": True,
                "statusMessage": "Doneko"
            }
        ]
    }
    new_groups.append(our)
    hooks[event_name] = new_groups

ensure_event("UserPromptSubmit", "started")
ensure_event("Stop", "completed")
ensure_event("Notification", "needsAttention")

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp, path)
print("    Claude hooks 已写入: UserPromptSubmit / Stop / Notification")
PY

# ---------- Codex hooks.json merge ----------
# Codex's single `notify` slot is often taken (e.g. by Computer Use), so Doneko
# uses lifecycle hooks instead. Other tools' hooks in the same file are kept.
CODEX_DIR="${HOME}/.codex"
CODEX_HOOKS="${CODEX_DIR}/hooks.json"
CODEX_CFG="${CODEX_DIR}/config.toml"
mkdir -p "${CODEX_DIR}"

echo "==> 合并 Codex hooks → ${CODEX_HOOKS}"
if [[ -f "${CODEX_HOOKS}" ]]; then
  cp "${CODEX_HOOKS}" "${CODEX_HOOKS}.doneko.bak.$(date +%Y%m%d%H%M%S)"
  echo "    已备份现有 hooks.json"
fi

/usr/bin/python3 - "${CODEX_HOOKS}" "${NOTIFY_DST}" <<'PY'
import json, os, shlex, sys

path, notify = sys.argv[1], sys.argv[2]
data = {}
if os.path.isfile(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        print("警告: ~/.codex/hooks.json 不是合法 JSON，未修改。")
        sys.exit(0)
if not isinstance(data, dict):
    data = {}
hooks = data.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}
    data["hooks"] = hooks

MARKERS = ("doneko-notify", "agentping-notify")

def is_ours(h):
    return isinstance(h, dict) and any(m in (h.get("command") or "") for m in MARKERS)

def ensure_event(event_name, kind):
    groups = hooks.get(event_name)
    if not isinstance(groups, list):
        groups = []
    new_groups = []
    for g in groups:
        if not isinstance(g, dict):
            new_groups.append(g)
            continue
        handlers = g.get("hooks") or []
        kept = [h for h in handlers if not is_ours(h)]
        if kept or not handlers:
            ng = dict(g)
            ng["hooks"] = kept
            new_groups.append(ng)
    new_groups.append({
        "hooks": [{
            "type": "command",
            "command": f"{shlex.quote(notify)} --source=codex --kind={kind}",
        }]
    })
    hooks[event_name] = new_groups

ensure_event("UserPromptSubmit", "started")
ensure_event("Stop", "completed")
ensure_event("PermissionRequest", "needsAttention")

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp, path)
print("    Codex hooks 已写入: UserPromptSubmit / Stop / PermissionRequest")
PY

# Older Doneko versions used Codex `notify`; drop only that line to avoid double alerts.
if [[ -f "${CODEX_CFG}" ]] && grep -Eq '^\s*notify\s*=.*(doneko-notify|agentping-notify)' "${CODEX_CFG}"; then
  cp "${CODEX_CFG}" "${CODEX_CFG}.doneko.bak.$(date +%Y%m%d%H%M%S)"
  /usr/bin/python3 - "${CODEX_CFG}" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
pat = re.compile(r"^\s*notify\s*=.*(doneko-notify|agentping-notify)")
out = [ln for ln in lines if not pat.match(ln)]
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("    已移除旧版 Doneko 的 Codex notify 行（其他 notify 保留）")
PY
fi
rm -f "${HOME}/.doneko/codex-hooks.example.json" 2>/dev/null || true

# ---------- Antigravity hooks.json merge ----------
# Global hooks live at ~/.gemini/config/hooks.json (CLI / App / IDE).
# PreInvocation / Stop use a flat handler list (no matcher wrapper).
AGY_BIN=""
if command -v agy >/dev/null 2>&1; then
  AGY_BIN="$(command -v agy)"
elif [[ -x "${HOME}/.local/bin/agy" ]]; then
  AGY_BIN="${HOME}/.local/bin/agy"
fi
if [[ -d "${HOME}/.gemini" || -n "${AGY_BIN}" ]]; then
  GEMINI_DIR="${HOME}/.gemini/config"
  GEMINI_HOOKS="${GEMINI_DIR}/hooks.json"
  mkdir -p "${GEMINI_DIR}"
  echo "==> 合并 Antigravity hooks → ${GEMINI_HOOKS}"
  if [[ -f "${GEMINI_HOOKS}" ]]; then
    cp "${GEMINI_HOOKS}" "${GEMINI_HOOKS}.doneko.bak.$(date +%Y%m%d%H%M%S)"
    echo "    已备份现有 hooks.json"
  fi
  /usr/bin/python3 - "${GEMINI_HOOKS}" "${NOTIFY_DST}" <<'PY'
import json, os, shlex, sys

path, notify = sys.argv[1], sys.argv[2]
data = {}
if os.path.isfile(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        print("警告: ~/.gemini/config/hooks.json 不是合法 JSON，未修改。")
        sys.exit(0)
if not isinstance(data, dict):
    data = {}

MARKERS = ("doneko-notify", "agentping-notify")

def handler_is_ours(h):
    return isinstance(h, dict) and any(m in (h.get("command") or "") for m in MARKERS)

def strip_ours(items):
    if not isinstance(items, list):
        return items, False
    changed = False
    out = []
    for item in items:
        if handler_is_ours(item):
            changed = True
            continue
        if isinstance(item, dict) and isinstance(item.get("hooks"), list):
            kept = [h for h in item["hooks"] if not handler_is_ours(h)]
            if len(kept) != len(item["hooks"]):
                changed = True
            if kept:
                ng = dict(item)
                ng["hooks"] = kept
                out.append(ng)
        else:
            out.append(item)
    return out, changed

for key, val in list(data.items()):
    if key == "doneko" or not isinstance(val, dict):
        continue
    new_def = dict(val)
    hook_changed = False
    for ev, items in list(new_def.items()):
        if ev == "enabled":
            continue
        cleaned, ch = strip_ours(items)
        if ch:
            hook_changed = True
            if cleaned:
                new_def[ev] = cleaned
            else:
                del new_def[ev]
    if hook_changed:
        data[key] = new_def

cmd = shlex.quote(notify)
data["doneko"] = {
    "enabled": True,
    "PreInvocation": [
        {"type": "command", "command": f"{cmd} --source=antigravity --kind=started", "timeout": 10}
    ],
    "Stop": [
        {"type": "command", "command": f"{cmd} --source=antigravity --kind=completed", "timeout": 10}
    ],
}

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp, path)
print("    Antigravity hooks 已写入: PreInvocation / Stop")
print("    在 agy 里输入 /hooks 可查看；如提示待信任，允许 Doneko")
PY
else
  echo "==> 未检测到 Antigravity / ~/.gemini，跳过 hooks"
fi

echo "==> 启动 Doneko…"
# Finder caches the icon until the bundle mtime changes.
touch "${APP_DIR}"
open "${APP_DIR}" || true

echo ""
echo "✓ 安装完成"
echo ""
echo "  应用:   ${APP_DIR}"
echo "  脚本:   ${NOTIFY_DST}"
echo "  套接字: ${HOME}/Library/Application Support/Doneko/doneko.sock"
echo ""
echo "首次使用提示:"
echo "  1. 系统会请求「通知」权限 — 请允许"
echo "  2. 点击通知跳转终端时，会请求「自动化」权限（Terminal / iTerm）— 请允许"
echo "  3. 菜单栏爪印 → 设置… 可开关各项效果，并点「测试」预览"
echo "  4. Claude Code: 新开一轮对话，提问后等待回答结束即可收到提示"
echo "  5. Codex: 新开一个会话即可；如 Codex 提示有新 hook 待信任，用 /hooks 允许 Doneko"
echo "  6. Antigravity（agy）: 新开一个会话即可；在 agy 里输入 /hooks 可查看 Doneko"
echo ""
echo "卸载: ${ROOT}/uninstall.sh"
