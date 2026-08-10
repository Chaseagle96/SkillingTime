import Foundation
import SwiftData

@Model
final class LifeSkill {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbolName: String
    var accentHex: String
    var category: String
    var createdAt: Date
    var sortOrder: Int
    var isArchived: Bool
    var progressionCurveVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        accentHex: String,
        category: String,
        createdAt: Date = .now,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        progressionCurveVersion: Int = ProgressionEngine.currentCurveVersion
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.category = category
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.progressionCurveVersion = progressionCurveVersion
    }
}

@Model
final class SkillSession {
    @Attribute(.unique) var id: UUID
    var skillID: UUID
    var startedAt: Date
    var endedAt: Date
    var activeSeconds: Int
    var note: String
    var sourceRawValue: String

    init(
        id: UUID = UUID(),
        skillID: UUID,
        startedAt: Date,
        endedAt: Date,
        activeSeconds: Int,
        note: String = "",
        source: SessionSource = .timer
    ) {
        self.id = id
        self.skillID = skillID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = max(0, activeSeconds)
        self.note = note
        self.sourceRawValue = source.rawValue
    }

    var source: SessionSource {
        SessionSource(rawValue: sourceRawValue) ?? .timer
    }

    /// The calendar instant used for history, Quest, and achievement attribution.
    /// A session is credited when the effort was completed rather than when it began.
    var creditedAt: Date { endedAt }
}

@Model
final class AchievementUnlock {
    @Attribute(.unique) var id: String
    var achievementID: String
    var skillID: UUID?
    var unlockedAt: Date
    var triggeringSessionID: UUID?

    init(
        id: String,
        achievementID: String,
        skillID: UUID?,
        unlockedAt: Date,
        triggeringSessionID: UUID?
    ) {
        self.id = id
        self.achievementID = achievementID
        self.skillID = skillID
        self.unlockedAt = unlockedAt
        self.triggeringSessionID = triggeringSessionID
    }

    static func identifier(achievementID: String, skillID: UUID?) -> String {
        if let skillID {
            return "\(achievementID)|\(skillID.uuidString.lowercased())"
        }
        return "\(achievementID)|global"
    }
}

@Model
final class ChronicleUnlock {
    @Attribute(.unique) var id: String
    var skillID: UUID
    var milestoneLevel: Int
    var unlockedAt: Date
    var triggeringSessionID: UUID

    init(
        id: String,
        skillID: UUID,
        milestoneLevel: Int,
        unlockedAt: Date,
        triggeringSessionID: UUID
    ) {
        self.id = id
        self.skillID = skillID
        self.milestoneLevel = milestoneLevel
        self.unlockedAt = unlockedAt
        self.triggeringSessionID = triggeringSessionID
    }

    static func identifier(skillID: UUID, milestoneLevel: Int) -> String {
        "chronicle-\(milestoneLevel)|\(skillID.uuidString.lowercased())"
    }
}

/// Rebuildable acceleration data. `SkillSession` remains authoritative.
@Model
final class SkillLedger {
    @Attribute(.unique) var skillID: UUID
    var totalActiveSeconds: Int
    var sessionCount: Int
    var longestSessionSeconds: Int
    var activeDayCount: Int
    var firstSessionAt: Date?
    var latestSessionAt: Date?
    var rebuiltAt: Date

    init(
        skillID: UUID,
        totalActiveSeconds: Int = 0,
        sessionCount: Int = 0,
        longestSessionSeconds: Int = 0,
        activeDayCount: Int = 0,
        firstSessionAt: Date? = nil,
        latestSessionAt: Date? = nil,
        rebuiltAt: Date = .now
    ) {
        self.skillID = skillID
        self.totalActiveSeconds = max(0, totalActiveSeconds)
        self.sessionCount = max(0, sessionCount)
        self.longestSessionSeconds = max(0, longestSessionSeconds)
        self.activeDayCount = max(0, activeDayCount)
        self.firstSessionAt = firstSessionAt
        self.latestSessionAt = latestSessionAt
        self.rebuiltAt = rebuiltAt
    }
}

/// Identity-only reward earned at Journeyman. It never changes XP.
@Model
final class SkillSpecialization {
    @Attribute(.unique) var skillID: UUID
    var title: String
    var chosenAt: Date

    init(skillID: UUID, title: String, chosenAt: Date = .now) {
        self.skillID = skillID
        self.title = title
        self.chosenAt = chosenAt
    }
}

enum SessionSource: String, Codable, Sendable {
    case timer
    case manual
}

struct SkillPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let symbolName: String
    let accentHex: String
    let category: String
}

enum BuiltInSkills {
    static let presets: [SkillPreset] = [
        .init(id: "cooking", name: "Cooking", symbolName: "frying.pan.fill", accentHex: "D97A43", category: "Home"),
        .init(id: "cleaning", name: "Cleaning", symbolName: "sparkles", accentHex: "55A7A2", category: "Home"),
        .init(id: "laundry", name: "Laundry", symbolName: "washer.fill", accentHex: "6E94C5", category: "Home"),
        .init(id: "landscaping", name: "Landscaping", symbolName: "leaf.fill", accentHex: "6D9E58", category: "Outdoors"),
        .init(id: "maintenance", name: "Home Maintenance", symbolName: "hammer.fill", accentHex: "B38255", category: "Home"),
        .init(id: "reading", name: "Reading", symbolName: "book.closed.fill", accentHex: "8A72B5", category: "Learning"),
        .init(id: "learning", name: "Learning", symbolName: "brain.head.profile", accentHex: "5D83C4", category: "Learning"),
        .init(id: "exercise", name: "Exercise", symbolName: "figure.run", accentHex: "C85E5E", category: "Wellbeing"),
        .init(id: "family", name: "Family Care", symbolName: "figure.and.child.holdinghands", accentHex: "C96E91", category: "Care"),
        .init(id: "pet-care", name: "Pet Care", symbolName: "pawprint.fill", accentHex: "B58B54", category: "Care"),
        .init(id: "organization", name: "Organization", symbolName: "tray.full.fill", accentHex: "648A8E", category: "Home"),
        .init(id: "creative", name: "Creative Practice", symbolName: "paintpalette.fill", accentHex: "A96AA2", category: "Creative")
    ]
}
