import SwiftUI
import UIKit

enum SkillingTimeTheme {
    static let background = Color(hex: "0E1117")
    static let secondaryBackground = Color(hex: "171C24")
    static let parchment = Color(hex: "F0DFC0")
    static let ink = Color(hex: "30251B")
    /// Accent colors deepen slightly in light mode so text stays readable.
    static let gold = Color(light: "9C7424", dark: "D8B263")
    static let mutedGold = Color(hex: "8F7441")
    static let success = Color(light: "3F8F55", dark: "78B984")
    static let danger = Color(light: "B04545", dark: "CD6A6A")

    static func rankColor(_ rank: SkillRank) -> Color {
        switch rank {
        case .novice: Color(light: "5F6878", dark: "7D8797")
        case .apprentice: Color(light: "8A5A2E", dark: "A9794B")
        case .journeyman: Color(light: "5E7288", dark: "A9B7C6")
        case .expert: Color(light: "A07A22", dark: "D4A94E")
        case .master: Color(light: "8F7A1C", dark: "D8C774")
        }
    }

    /// The launch splash keeps its dark brand look, except in Black mode where it
    /// is pure black like everything else.
    static func splashBackground(for appearance: AppAppearance) -> Color {
        appearance == .black ? .black : background
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case black
    case system

    static let storageKey = "appearance.mode"
    static let defaultValue = AppAppearance.dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .black: "Black (OLED)"
        case .system: "Match System"
        }
    }

    /// Black is a dark color scheme with pure-black backgrounds.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark, .black: .dark
        case .light: .light
        case .system: nil
        }
    }
}

private struct AppAppearanceKey: EnvironmentKey {
    static let defaultValue = AppAppearance.defaultValue
}

extension EnvironmentValues {
    var skillingTimeAppearance: AppAppearance {
        get { self[AppAppearanceKey.self] }
        set { self[AppAppearanceKey.self] = newValue }
    }
}

extension Color {
    /// A color that follows the active light or dark appearance.
    init(light: String, dark: String) {
        let lightColor = UIColor(Color(hex: light))
        let darkColor = UIColor(Color(hex: dark))
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? lightColor : darkColor
        })
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        switch cleaned.count {
        case 8:
            red = value >> 24
            green = (value >> 16) & 0xFF
            blue = (value >> 8) & 0xFF
            alpha = value & 0xFF
        default:
            red = value >> 16
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
            alpha = 0xFF
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func sessionComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func sessionStart() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.78)
    }

    static func questComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func rewardReveal() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
    }

    static func levelUp(major: Bool) {
        if major {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
            }
        } else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
        }
    }
}
