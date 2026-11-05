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

# ---------- Codex config.toml ----------
CODEX_DIR="${HOME}/.codex"
CODEX_CFG="${CODEX_DIR}/config.toml"
mkdir -p "${CODEX_DIR}"

echo "==> 配置 Codex notify → ${CODEX_CFG}"
if [[ -f "${CODEX_CFG}" ]]; then
  cp "${CODEX_CFG}" "${CODEX_CFG}.doneko.bak.$(date +%Y%m%d%H%M%S)"
  echo "    已备份现有 config.toml"
fi

/usr/bin/python3 - "${CODEX_CFG}" "${NOTIFY_DST}" <<'PY'
import os, sys, re

path, notify = sys.argv[1], sys.argv[2]
text = ""
if os.path.isfile(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

# Detect existing top-level notify =
# Simple scan: lines before any [table] that look like notify =
lines = text.splitlines()
before_table = []
rest = []
hit_table = False
for line in lines:
    if not hit_table and re.match(r"^\s*\[", line):
        hit_table = True
    if hit_table:
        rest.append(line)
    else:
        before_table.append(line)

notify_re = re.compile(r"^\s*notify\s*=", re.I)
existing = [ln for ln in before_table if notify_re.match(ln)]
ours_line = f'notify = ["{notify}", "--source=codex", "--kind=completed"]'

if existing:
    joined = "\n".join(existing)
    if "doneko-notify" in joined or "agentping-notify" in joined:
        # Replace previous Doneko / legacy AgentPing line(s)
        before_table = [ln for ln in before_table if not (
            notify_re.match(ln) and ("doneko-notify" in ln or "agentping-notify" in ln)
        )]
        # If other notify remains, warn; else write ours
        still = [ln for ln in before_table if notify_re.match(ln)]
        if still:
            print("警告: ~/.codex/config.toml 仍有其他 notify，已移除旧 Doneko/AgentPing 行但未写入新行。")
            for ln in still:
                print(f"        {ln}")
        else:
            before_table.append(ours_line)
            print("    已更新现有 Doneko/AgentPing notify 行")
    else:
        print("警告: ~/.codex/config.toml 已有 notify 配置，未覆盖。")
        print("      现有内容:")
        for ln in existing:
            print(f"        {ln}")
        print(f"      如需使用 Doneko，请手动改为:\n        {ours_line}")
        sys.exit(0)
else:
    # Insert near top, after any comments
    insert_at = 0
    for i, ln in enumerate(before_table):
        if ln.strip() and not ln.strip().startswith("#"):
            insert_at = i
            break
        insert_at = i + 1
    before_table.insert(insert_at, ours_line)
    before_table.insert(insert_at + 1, "")
    print("    已写入 notify 配置")

# Optional: also hint about Codex lifecycle hooks for "started"
hooks_path = os.path.join(os.path.dirname(path), "hooks.json")
# We don't auto-write hooks.json (requires /hooks trust). Document in README.

new_text = "\n".join(before_table + rest)
if not new_text.endswith("\n"):
    new_text += "\n"
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    f.write(new_text)
os.replace(tmp, path)
PY

# Optional Codex started hook helper file (not auto-enabled — needs trust)
CODEX_HOOKS_EXAMPLE="${HOME}/.doneko/codex-hooks.example.json"
/usr/bin/python3 - "${CODEX_HOOKS_EXAMPLE}" "${NOTIFY_DST}" <<'PY'
import json, sys
path, notify = sys.argv[1], sys.argv[2]
data = {
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": notify,
            "args": ["--source=codex", "--kind=started"],
            "timeout": 5,
            "statusMessage": "Doneko"
          }
        ]
      }
    ]
  }
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"    已生成 Codex 开始事件示例: {path}")
print("    （Codex notify 仅有 agent-turn-complete；如需菜单栏「工作中」动画，")
print("     可将示例合并到 ~/.codex/hooks.json 并在 Codex 中 /hooks 信任）")
PY

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
echo "  5. Codex: 完成一轮 turn 后触发 notify"
echo ""
echo "卸载: ${ROOT}/uninstall.sh"
