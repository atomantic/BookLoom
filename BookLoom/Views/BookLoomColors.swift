import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum BookLoomStyle {
    static let ink = adaptiveColor(
        light: RGB(0.13, 0.12, 0.15),
        dark: RGB(0.97, 0.92, 0.84)
    )
    static let paper = Color(red: 0.965, green: 0.898, blue: 0.804)
    static let parchment = Color(red: 0.91, green: 0.80, blue: 0.64)
    static let indigo = adaptiveColor(
        light: RGB(0.13, 0.18, 0.38),
        dark: RGB(0.58, 0.65, 0.94)
    )
    static let plum = adaptiveColor(
        light: RGB(0.42, 0.25, 0.53),
        dark: RGB(0.76, 0.57, 0.84)
    )
    static let sage = adaptiveColor(
        light: RGB(0.37, 0.49, 0.34),
        dark: RGB(0.66, 0.76, 0.57)
    )
    static let coral = adaptiveColor(
        light: RGB(0.80, 0.31, 0.21),
        dark: RGB(0.96, 0.48, 0.35)
    )
    static let gold = adaptiveColor(
        light: RGB(0.83, 0.60, 0.24),
        dark: RGB(0.94, 0.72, 0.36)
    )

    static func screenGradient(for colorScheme: ColorScheme) -> LinearGradient {
        let colors: [Color]
        if colorScheme == .dark {
            colors = [
                Color(red: 0.09, green: 0.08, blue: 0.10),
                Color(red: 0.12, green: 0.13, blue: 0.18),
                Color(red: 0.18, green: 0.13, blue: 0.20)
            ]
        } else {
            colors = [
                BookLoomStyle.paper,
                BookLoomStyle.paper
            ]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private struct RGB {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
            self.red = CGFloat(red)
            self.green = CGFloat(green)
            self.blue = CGFloat(blue)
            self.alpha = CGFloat(alpha)
        }
    }

    private static func adaptiveColor(light: RGB, dark: RGB) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let color = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        })
        #elseif os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let color = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        })
        #else
        Color(red: Double(light.red), green: Double(light.green), blue: Double(light.blue), opacity: Double(light.alpha))
        #endif
    }
}
