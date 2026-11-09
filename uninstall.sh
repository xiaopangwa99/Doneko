#!/usr/bin/env bash
# Doneko uninstaller — remove app, script, and Doneko/legacy AgentPing hook entries
set -euo pipefail

APP_DIR="${HOME}/Applications/Doneko.app"
LEGACY_APP_DIR="${HOME}/Applications/AgentPing.app"
SUPPORT_BIN="${HOME}/.doneko/bin"
NOTIFY_DST="${SUPPORT_BIN}/doneko-notify"
LEGACY_BIN="${HOME}/.agentping/bin/agentping-notify"
SOCK="${HOME}/Library/Application Support/Doneko/doneko.sock"
LEGACY_SOCK="${HOME}/Library/Application Support/AgentPing/agentping.sock"

echo "==> 卸载 Doneko"

pkill -x Doneko 2>/dev/null || true
pkill -x AgentPing 2>/dev/null || true
sleep 0.3

if [[ -d "${APP_DIR}" ]]; then
  rm -rf "${APP_DIR}"
  echo "    已删除 ${APP_DIR}"
fi
if [[ -d "${LEGACY_APP_DIR}" ]]; then
  rm -rf "${LEGACY_APP_DIR}"
  echo "    已删除旧版 ${LEGACY_APP_DIR}"
fi

rm -f "${NOTIFY_DST}" 2>/dev/null || true
rm -f "${LEGACY_BIN}" 2>/dev/null || true
rm -f "${SOCK}" "${LEGACY_SOCK}" 2>/dev/null || true
echo "    已删除 notify 脚本与套接字（含旧 AgentPing）"

CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
if [[ -f "${CLAUDE_SETTINGS}" ]]; then
  cp "${CLAUDE_SETTINGS}" "${CLAUDE_SETTINGS}.doneko.uninstall.bak.$(date +%Y%m%d%H%M%S)"
  /usr/bin/python3 - "${CLAUDE_SETTINGS}" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    try:
        data = json.load(f)
    except Exception:
        sys.exit(0)
hooks = data.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(0)
MARKERS = ("doneko-notify", "agentping-notify")

def is_ours(handler):
    if not isinstance(handler, dict):
        return False
    cmd = handler.get("command") or ""
    args = handler.get("args") or []
    blob = cmd + " " + " ".join(args if isinstance(args, list) else [])
    return any(m in blob for m in MARKERS)

changed = False
for event, groups in list(hooks.items()):
    if not isinstance(groups, list):
        continue
    new_groups = []
    for g in groups:
        if not isinstance(g, dict):
            new_groups.append(g)
            continue
        handlers = g.get("hooks") or []
        kept = [h for h in handlers if not is_ours(h)]
        if len(kept) != len(handlers):
            changed = True
        if kept:
            ng = dict(g)
            ng["hooks"] = kept
            new_groups.append(ng)
    if new_groups:
        hooks[event] = new_groups
    else:
        del hooks[event]
        changed = True

if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("    已从 ~/.claude/settings.json 移除 Doneko / AgentPing hooks")
else:
    print("    Claude settings 中无 Doneko/AgentPing hooks")
PY
fi

CODEX_HOOKS="${HOME}/.codex/hooks.json"
if [[ -f "${CODEX_HOOKS}" ]]; then
  cp "${CODEX_HOOKS}" "${CODEX_HOOKS}.doneko.uninstall.bak.$(date +%Y%m%d%H%M%S)"
  /usr/bin/python3 - "${CODEX_HOOKS}" <<'PY'
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception:
    sys.exit(0)
hooks = data.get("hooks") if isinstance(data, dict) else None
if not isinstance(hooks, dict):
    sys.exit(0)
MARKERS = ("doneko-notify", "agentping-notify")
changed = False
for event, groups in list(hooks.items()):
    if not isinstance(groups, list):
        continue
    new_groups = []
    for g in groups:
        if not isinstance(g, dict):
            new_groups.append(g)
            continue
        handlers = g.get("hooks") or []
        kept = [h for h in handlers if not (isinstance(h, dict) and any(m in (h.get("command") or "") for m in MARKERS))]
        if len(kept) != len(handlers):
            changed = True
        if kept:
            ng = dict(g)
            ng["hooks"] = kept
            new_groups.append(ng)
    if new_groups:
        hooks[event] = new_groups
    else:
        del hooks[event]
if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("    已从 ~/.codex/hooks.json 移除 Doneko hooks（其他工具的保留）")
else:
    print("    Codex hooks.json 中无 Doneko hooks")
PY
fi

CODEX_CFG="${HOME}/.codex/config.toml"
if [[ -f "${CODEX_CFG}" ]]; then
  cp "${CODEX_CFG}" "${CODEX_CFG}.doneko.uninstall.bak.$(date +%Y%m%d%H%M%S)"
  /usr/bin/python3 - "${CODEX_CFG}" <<'PY'
import sys, re
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()
notify_re = re.compile(r"^\s*notify\s*=", re.I)
out = []
removed = False
for ln in lines:
    if notify_re.match(ln) and ("doneko-notify" in ln or "agentping-notify" in ln):
        removed = True
        continue
    out.append(ln)
if removed:
    text = "\n".join(out)
    if not text.endswith("\n"):
        text += "\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("    已从 ~/.codex/config.toml 移除 Doneko / AgentPing notify")
else:
    print("    Codex config 中无 Doneko/AgentPing notify（其他 notify 已保留）")
PY
fi

echo ""
echo "✓ 卸载完成"
echo "  历史记录仍可保留在 ~/Library/Application Support/Doneko/ （可手动删除）"
echo "  旧版数据目录 ~/Library/Application Support/AgentPing/ 与 ~/.agentping/ 也可手动删除"
echo "  如曾开启「登录时启动」，可在 系统设置 → 通用 → 登录项 中移除 Doneko"
