import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "net.shadowpuppet.BookLoom.appearance"
    static let legacyStorageKey = "net.shadowpuppet.PlotLoom.appearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func resolved(from rawValue: String) -> AppAppearance {
        AppAppearance(rawValue: rawValue) ?? .system
    }
}

enum WelcomeReplay {
    static let storageKey = "net.shadowpuppet.BookLoom.replayWelcome"
    static let legacyStorageKey = "net.shadowpuppet.PlotLoom.replayWelcome"
}

enum LegacyDefaultsMigration {
    static func migrateBookLoomKeys() {
        let defaults = UserDefaults.standard
        copyString(from: AppAppearance.legacyStorageKey, to: AppAppearance.storageKey, defaults: defaults)
        copyBool(from: WelcomeReplay.legacyStorageKey, to: WelcomeReplay.storageKey, defaults: defaults)
    }

    private static func copyString(from oldKey: String, to newKey: String, defaults: UserDefaults) {
        guard defaults.object(forKey: newKey) == nil,
              let oldValue = defaults.string(forKey: oldKey) else {
            return
        }
        defaults.set(oldValue, forKey: newKey)
    }

    private static func copyBool(from oldKey: String, to newKey: String, defaults: UserDefaults) {
        guard defaults.object(forKey: newKey) == nil,
              defaults.object(forKey: oldKey) != nil else {
            return
        }
        defaults.set(defaults.bool(forKey: oldKey), forKey: newKey)
    }
}
