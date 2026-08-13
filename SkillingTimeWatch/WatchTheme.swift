import Foundation
import SwiftUI

enum SkillingTimeWatchTheme {
    static let gold = Color(red: 0.96, green: 0.72, blue: 0.24)
    static let secondaryGold = Color(red: 0.74, green: 0.53, blue: 0.17)
    static let success = Color(red: 0.32, green: 0.84, blue: 0.58)
    static let danger = Color(red: 0.96, green: 0.36, blue: 0.34)
    static let muted = Color.secondary

    static func accent(_ hex: String) -> Color {
        let normalized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count == 6,
              let value = UInt64(normalized, radix: 16) else {
            return gold
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum WatchDurationFormatter {
    static func timer(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let remainingSeconds = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func compact(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        if clamped >= 3600 {
            return "\(clamped / 3600)h"
        }
        if clamped >= 60 {
            return "\(clamped / 60)m"
        }
        return "\(clamped)s"
    }
}
