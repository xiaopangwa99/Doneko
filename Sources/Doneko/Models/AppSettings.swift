import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var enableSystemNotification: Bool {
        didSet { defaults.set(enableSystemNotification, forKey: Keys.enableSystemNotification) }
    }
    @Published var enableCapsule: Bool {
        didSet { defaults.set(enableCapsule, forKey: Keys.enableCapsule) }
    }
    @Published var enableEdgeGlow: Bool {
        didSet { defaults.set(enableEdgeGlow, forKey: Keys.enableEdgeGlow) }
    }
    @Published var enableMenuBarAnimation: Bool {
        didSet { defaults.set(enableMenuBarAnimation, forKey: Keys.enableMenuBarAnimation) }
    }
    @Published var suppressWhenFocused: Bool {
        didSet { defaults.set(suppressWhenFocused, forKey: Keys.suppressWhenFocused) }
    }
    @Published var capsuleDuration: Double {
        didSet { defaults.set(capsuleDuration, forKey: Keys.capsuleDuration) }
    }
    @Published var notificationSound: String {
        didSet { defaults.set(notificationSound, forKey: Keys.notificationSound) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LoginItemManager.shared.setEnabled(launchAtLogin)
        }
    }

    /// System sounds from /System/Library/Sounds. Default soft "Purr" fits the cat theme.
    /// A synthesized "meow" is not bundled (no copyrighted assets); use Purr/Glass instead.
    static let systemSounds: [String] = [
        "Purr", "Glass", "Ping", "Pop", "Bottle", "Funk", "Hero", "Sosumi", "Submarine", "Tink"
    ]

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enableSystemNotification = "doneko.enableSystemNotification"
        static let enableCapsule = "doneko.enableCapsule"
        static let enableEdgeGlow = "doneko.enableEdgeGlow"
        static let enableMenuBarAnimation = "doneko.enableMenuBarAnimation"
        static let suppressWhenFocused = "doneko.suppressWhenFocused"
        static let capsuleDuration = "doneko.capsuleDuration"
        static let notificationSound = "doneko.notificationSound"
        static let launchAtLogin = "doneko.launchAtLogin"
    }

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: String, default def: Bool) -> Bool {
            if d.object(forKey: key) == nil { return def }
            return d.bool(forKey: key)
        }
        enableSystemNotification = bool(Keys.enableSystemNotification, default: true)
        enableCapsule = bool(Keys.enableCapsule, default: true)
        enableEdgeGlow = bool(Keys.enableEdgeGlow, default: true)
        enableMenuBarAnimation = bool(Keys.enableMenuBarAnimation, default: true)
        suppressWhenFocused = bool(Keys.suppressWhenFocused, default: true)
        capsuleDuration = d.object(forKey: Keys.capsuleDuration) as? Double ?? 4.0
        notificationSound = d.string(forKey: Keys.notificationSound) ?? "Purr"
        launchAtLogin = bool(Keys.launchAtLogin, default: false)
    }
}
