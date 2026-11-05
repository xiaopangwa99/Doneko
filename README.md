# Doneko

> **done** + **neko**（日语「猫」）— macOS 菜单栏小猫，在 Claude Code / Codex CLI 回答结束后轻轻提醒你。

- 事件驱动，无轮询；平时几乎不占 CPU
- 原生 Swift / SwiftUI / AppKit（非 Electron）
- 要求 macOS 13+
- UI 为简体中文；菜单栏是一只小猫 🐱

## 功能

| 效果 | 说明 | 默认 |
| --- | --- | --- |
| 系统通知 | 横幅 + 系统提示音（默认柔和的 **Purr**），点击跳回终端 | 开 |
| 顶部胶囊 | 灵动岛式提示，带小猫图标，可点 | 开 |
| 边缘柔光 | 全屏点击穿透的彩色光晕（Claude 偏橙 / Codex 偏蓝） | 开 |
| 菜单栏小猫 | 空闲猫；工作中轻微脉冲/耳朵动画；未读橙点 | 开 |
| 前台不打扰 | 来源终端已在前台则不弹提醒 | 开 |
| 登录启动 | 通过 `SMAppService` 注册 | 关 |

菜单栏可查看最近完成记录；点击一条即可跳回 Terminal.app / iTerm2（按 tty / session id），或其它终端（按 `TERM_PROGRAM` 激活）。

> 未内置独立「喵叫」音频文件（避免版权素材）；请使用系统音效 **Purr** / **Glass** 等。

## 安装

在 **Mac** 上（需已安装 Xcode 或 Command Line Tools）：

```bash
cd /path/to/Doneko
./install.sh
```

脚本会：

1. `swift build -c release`
2. 组装 `~/Applications/Doneko.app`（`LSUIElement`，无 Dock 图标）并 ad-hoc 签名
3. 安装 `~/.doneko/bin/doneko-notify`
4. 安全合并 hooks 到 `~/.claude/settings.json`（先备份；同时清掉旧版 AgentPing hooks）
5. 写入 `notify` 到 `~/.codex/config.toml`（若已有非 Doneko 的 notify，**不会覆盖**，只打印警告）
6. 启动应用

## 如何测试

### 应用内测试

菜单栏小猫 → **设置…** → **测试 Claude Code / 测试 Codex**

### 手动打脚本

```bash
echo '{"session_id":"t1","cwd":"/tmp/demo","hook_event_name":"Stop","last_assistant_message":"搞定了"}' \
  | ~/.doneko/bin/doneko-notify --source=claude --kind=completed

~/.doneko/bin/doneko-notify --source=codex --kind=completed \
  '{"type":"agent-turn-complete","cwd":"/tmp/demo","last-assistant-message":"Build passed."}'
```

### 真实 Agent

1. 确认菜单栏有小猫图标
2. Claude Code：提问并等待回答结束
3. Codex：完成一轮 turn

## 卸载

```bash
./uninstall.sh
```

会删除 App、notify 脚本，并从 Claude / Codex 配置中移除 **Doneko 与旧版 AgentPing** 写入的条目。

## 架构说明

```
Claude Code hooks / Codex notify
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
   Doneko.app（菜单栏小猫）
```

### Claude Code

- `UserPromptSubmit` → `started`（小猫进入工作中动画）
- `Stop` → `completed`
- `Notification` → `needsAttention`

stdin 为 Claude 官方 JSON。若 `stop_hook_active == true` 则静默退出。

### Codex CLI

```toml
notify = ["/Users/你/.doneko/bin/doneko-notify", "--source=codex", "--kind=completed"]
```

JSON 作为**最后一个 argv**（stdin 为 null）。`notify` 目前只有 `agent-turn-complete`，没有官方「开始」事件。可选参考 `~/.doneko/codex-hooks.example.json`。

## 权限提示（首次）

1. **通知** → 允许  
2. **自动化**（跳回 Terminal / iTerm）→ 允许  
3. Gatekeeper：右键 App → 打开  

## 故障排查

| 现象 | 排查 |
| --- | --- |
| 完全没反应 | 确认菜单栏有小猫；看 `~/.doneko/logs/notify.log` |
| 只有通知、没有胶囊 | 设置是否关闭了胶囊；是否「前台不打扰」 |
| Claude 不触发 | `/hooks` 是否有 Doneko；检查 `~/.claude/settings.json` |
| Codex 不触发 | `notify` 须在用户 `~/.codex/config.toml` **顶层** |
| 跳转失败 | 隐私与安全性 → 自动化 → 勾选 Doneko |

```bash
ls -l ~/Library/Application\ Support/Doneko/doneko.sock
```

## 开发

```bash
swift build -c release
# 产物一般在 .build/release/Doneko
```

Bundle ID：`com.yiming.doneko` · URL Scheme：`doneko://` · MIT License

## 许可

MIT © 2026 YIMING YUAN
