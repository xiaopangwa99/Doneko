import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("提醒效果") {
                Toggle("系统通知横幅 + 提示音", isOn: $settings.enableSystemNotification)
                Picker("提示音", selection: $settings.notificationSound) {
                    ForEach(AppSettings.systemSounds, id: \.self) { name in
                        Text(name == "Purr" ? "Purr（推荐）" : name).tag(name)
                    }
                }
                .disabled(!settings.enableSystemNotification)

                Toggle("灵动岛式顶部胶囊", isOn: $settings.enableCapsule)
                HStack {
                    Text("胶囊显示时长")
                    Slider(value: $settings.capsuleDuration, in: 2...10, step: 0.5)
                    Text(String(format: "%.1f 秒", settings.capsuleDuration))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                .disabled(!settings.enableCapsule)

                Toggle("屏幕边缘柔光", isOn: $settings.enableEdgeGlow)
                Toggle("菜单栏爪印动画", isOn: $settings.enableMenuBarAnimation)
            }

            Section("行为") {
                Toggle("终端前台时不打扰", isOn: $settings.suppressWhenFocused)
                Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
            }

            Section("测试") {
                HStack {
                    Button("测试 Claude Code") {
                        EventRouter.shared.testAlert(source: .claude)
                    }
                    Button("测试 Codex") {
                        EventRouter.shared.testAlert(source: .codex)
                    }
                    Button("测试 Antigravity") {
                        EventRouter.shared.testAlert(source: .antigravity)
                    }
                }
                Text("会强制弹出全部已开启的效果（忽略「不打扰」）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("应用", value: "Doneko（done + neko 猫）")
                LabeledContent("版本", value: "1.0.0")
                LabeledContent("套接字", value: SocketServer.shared.socketPath)
                    .font(.system(.caption, design: .monospaced))
                Text("点击通知 / 胶囊 / 菜单项可跳回对应终端。首次跳转时 macOS 可能请求「自动化」权限。默认提示音为柔和的 Purr；未内置独立喵叫音频（避免版权素材）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 480)
    }
}
