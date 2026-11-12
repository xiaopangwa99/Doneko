# Doneko

> **done** + **neko**（日语「猫」）— macOS 菜单栏爪印，在 Claude Code / Codex / Antigravity CLI 回答结束后轻轻提醒你。

- 事件驱动，无轮询；平时几乎不占 CPU
- 原生 Swift / SwiftUI / AppKit（非 Electron）
- 要求 macOS 13+
- UI 为简体中文；菜单栏是一枚猫爪印

## 功能

| 效果 | 说明 | 默认 |
| --- | --- | --- |
| 系统通知 | 横幅 + 系统提示音（默认柔和的 **Purr**），点击跳回终端 | 开 |
| 顶部胶囊 | 灵动岛式提示，带爪印，可点 | 开 |
| 边缘柔光 | 全屏点击穿透的彩色光晕（Claude 偏橙 / Codex 偏蓝 / Antigravity 偏绿） | 开 |
| 菜单栏爪印 | 空闲为单色模板爪印；工作中轻微跳动；未读时整枚爪印变为橙色（打开菜单或读完后恢复） | 开 |
| 前台不打扰 | 来源终端已在前台则不弹提醒 | 开 |
| 登录启动 | 通过 `SMAppService` 注册 | 关 |

菜单栏历史每个会话只保留最新一条，灰色第二行是回复摘要；点击一条即可跳回对应终端：

- **Ghostty**（推荐 ≥ **1.4.0**）：按 tty 精确定位到具体 terminal / tab；无 tty 时回退到工作目录匹配（同目录多 tab 可能不准）
- **Terminal.app / iTerm2**：按 tty / session id（iTerm 会解析 `ITERM_SESSION_ID` 冒号后的 UUID）
- 其它终端：按 `TERM_PROGRAM` 激活整个应用

Ghostty AppleScript 支持自 **1.3.0** 起；按 tty 聚焦需要 **≥ 1.4.0**。首次跳转需在「系统设置 → 隐私与安全性 → 自动化」允许 Doneko 控制 Ghostty。

> 未内置独立「喵叫」音频文件（避免版权素材）；请使用系统音效 **Purr** / **Glass** 等。

## 安装

在 **Mac** 上（需已安装 Xcode 或 Command Line Tools）：

```bash
cd /path/to/Doneko
./install.sh
```

脚本会：

1. `swift build -c release`
2. 组装 `~/Applications/Doneko.app`（`LSUIElement`，无 Dock 图标；Finder 图标为橙色圆角爪印）并 ad-hoc 签名
3. 安装 `~/.doneko/bin/doneko-notify`
4. 安全合并 hooks 到 `~/.claude/settings.json`（先备份；同时清掉旧版 AgentPing hooks）
5. 把 Doneko 的 handlers 合并进 `~/.codex/hooks.json`（`UserPromptSubmit` / `Stop` / `PermissionRequest`；其它工具的 hooks 会保留）。已有的 `notify` **保持不动**（只会删掉旧版 Doneko 自己写过的那一行，避免和 hooks 重复提醒）。首次需在 Codex 里用 `/hooks` 信任这些 hook
6. 若已安装 Antigravity（存在 `~/.gemini` 或 `agy`），把 Doneko 合并进 `~/.gemini/config/hooks.json`（`PreInvocation` / `Stop`；其它 hook 保留）。在 `agy` 里输入 `/hooks` 可查看
7. 启动应用

## 如何测试

### 应用内测试

菜单栏爪印 → **设置…** → **测试 Claude Code / 测试 Codex / 测试 Antigravity**

### 手动打脚本

```bash
echo '{"session_id":"t1","cwd":"/tmp/demo","hook_event_name":"Stop","last_assistant_message":"搞定了"}' \
  | ~/.doneko/bin/doneko-notify --source=claude --kind=completed

~/.doneko/bin/doneko-notify --source=codex --kind=completed \
  '{"type":"agent-turn-complete","cwd":"/tmp/demo","last-assistant-message":"Build passed."}'

# Antigravity Stop：脚本会向 stdout 打印 {"decision":"stop"}；DONEKO_DRY_RUN=1 只解析不投递
printf '%s' '{"conversationId":"t1","workspacePaths":["/tmp/demo"],"fullyIdle":true,"terminationReason":"model_stop","lastUserInput":"hi","transcriptPath":"/tmp/missing.jsonl"}' \
  | DONEKO_DRY_RUN=1 ~/.doneko/bin/doneko-notify --source=antigravity --kind=completed
```

### 真实 Agent

1. 确认菜单栏有爪印
2. Claude Code：提问并等待回答结束
3. Codex：提问后爪印进入工作中，回答结束或请求权限时提醒（需已用 `/hooks` 信任）
4. Antigravity（`agy`）：提问后爪印进入工作中，回答结束后提醒。在 `agy` 里输入 `/hooks` 可查看 Doneko

## 卸载

```bash
./uninstall.sh
```

会删除 App、notify 脚本，并从 Claude settings、Codex `hooks.json` 与 Antigravity `~/.gemini/config/hooks.json` 中移除 **Doneko 与旧版 AgentPing** 写入的条目（`config.toml` 里旧版 Doneko 的 `notify` 行也会删掉，其它 `notify` 保留）。

## 架构说明

```
Claude Code hooks / Codex hooks / Antigravity hooks
        │
        ▼
 ~/.doneko/bin/doneko-notify   （立刻后台投递后 exit 0）
        │
        ├─ Unix domain socket（首选）
        │     ~/Library/Application Support/Doneko/doneko.sock
        ├─ open doneko://event?json=…（App 未运行时拉起）
        └─ osascript 通知（兜底）
        │
        ▼
   Doneko.app（菜单栏爪印）
```

### Claude Code

- `UserPromptSubmit` → `started`（爪印进入工作中动画）
- `Stop` → `completed`
- `Notification` → `needsAttention`

stdin 为 Claude 官方 JSON。若 `stop_hook_active == true` 则静默退出。

### Codex CLI

安装写入的是 `~/.codex/hooks.json`，不再占用 `config.toml` 里那一个 `notify` 槽。现在有开始事件，菜单栏「工作中」动画会跟着走。Codex 会要求你用 `/hooks` **信任一次** 这些新 hook。

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

- `UserPromptSubmit` → `started`（爪印进入工作中动画）
- `Stop` → `completed`
- `PermissionRequest` → `needsAttention`

事件 JSON 由 Codex 经 stdin 传入。

### Antigravity CLI

安装时若检测到 `~/.gemini` 或 `agy`，会把 Doneko 写入全局 `~/.gemini/config/hooks.json`（CLI / App / IDE 共用）。`PreInvocation` 与 `Stop` 必须是扁平的 handler 列表，不能套 `matcher` / `hooks` 那一层。

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

- `PreInvocation` → `started`（每次调用模型前；爪印进入工作中动画）
- `Stop` → `completed`（仅在 `fullyIdle` 为 true 时提醒；仍有后台任务时跳过，等下一次 Stop）

Stop hook **必须**在 stdout 打印 `{"decision":"stop"}`。若写成 `"continue"`，agent 会重新进入循环。其它 hook 保持快速退出、不打印决策即可。

会话 id 使用 `conversationId`，工作目录取 `workspacePaths[0]`，摘要优先读 `transcriptPath` 里最后一条模型回复（`PLANNER_RESPONSE` 的 `content`），没有则回退为「任务完成」。若 `terminationReason` 为 `error`，摘要会加上「出错：」前缀。

**限制：** Antigravity 没有「等待许可 / 需要输入」这类 hook，因此不会发出「需要关注」提醒。

在 `agy` 里输入 `/hooks` 可查看当前已加载的 hook。

## 权限提示（首次）

1. **通知** → 允许  
2. **自动化**（跳回 Terminal / iTerm / **Ghostty**）→ 允许 Doneko 控制对应终端  
3. Gatekeeper：右键 App → 打开  

> Ghostty：请升级到 **≥ 1.4** 以获得按 tty 精跳；1.3 仅有 AppleScript / 工作目录匹配。若提示自动化权限被拒，Doneko 不会假装跳转成功。

## 故障排查

| 现象 | 排查 |
| --- | --- |
| 完全没反应 | 确认菜单栏有爪印；看 `~/.doneko/logs/notify.log` |
| 只有通知、没有胶囊 | 设置是否关闭了胶囊；是否「前台不打扰」 |
| Claude 不触发 | `/hooks` 是否有 Doneko；检查 `~/.claude/settings.json` |
| Codex 不触发 | 确认 `~/.codex/config.toml` 里 `[features] hooks = true`；在 Codex 中用 `/hooks` 信任 Doneko |
| Antigravity 不触发 | 确认 `~/.gemini/config/hooks.json` 有 `doneko`；在 `agy` 里输入 `/hooks` 查看 |
| 跳转失败 | 隐私与安全性 → 自动化 → 勾选 Doneko（含 Ghostty） |
| Ghostty 只激活窗口、不切 tab | 升级到 Ghostty ≥ 1.4；确认 hook 采集到了 tty（看事件 JSON / notify 日志） |
| 同目录多个 Ghostty tab 跳错 | 正常：无 tty 时只能按 cwd 猜；修好 tty 采集后按 tty 精跳 |

```bash
ls -l ~/Library/Application\ Support/Doneko/doneko.sock
```

## 开发

```bash
swift build -c release
# 产物一般在 .build/release/Doneko

# 重新生成 App 图标（需要 Pillow）。install.sh 会在 Mac 上用 iconutil 打成 icns。
python3 Scripts/render-app-icon.py
```

Bundle ID：`com.yiming.doneko` · URL Scheme：`doneko://` · MIT License

## 许可

MIT © 2026 YIMING YUAN
