import SwiftUI
import UIKit

enum SkillingTimeTheme {
    static let background = Color(hex: "0E1117")
    static let secondaryBackground = Color(hex: "171C24")
    static let parchment = Color(hex: "F0DFC0")
    static let ink = Color(hex: "30251B")
    static let gold = Color(hex: "D8B263")
    static let mutedGold = Color(hex: "8F7441")
    static let success = Color(hex: "78B984")
    static let danger = Color(hex: "CD6A6A")

    static func rankColor(_ rank: SkillRank) -> Color {
        switch rank {
        case .novice: Color(hex: "7D8797")
        case .apprentice: Color(hex: "A9794B")
        case .journeyman: Color(hex: "A9B7C6")
        case .expert: Color(hex: "D4A94E")
        case .master: Color(hex: "D8C774")
        }
    }
}

extension Color {
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
