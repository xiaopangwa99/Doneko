import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager {
    static let shared = LoginItemManager()

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Doneko: 开机启动设置失败: \(error.localizedDescription)")
        }
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
