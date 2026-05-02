import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "net.shadowpuppet.PlotLoom.appearance"

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
    static let storageKey = "net.shadowpuppet.PlotLoom.replayWelcome"
}
