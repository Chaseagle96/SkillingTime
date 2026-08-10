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
    var focusGoalKindRawValue: String?
    var focusGoalTargetValue: Int?
    var focusGoalStartingTotalXP: Int?
    var focusGoalCompletedRawValue: Bool?

    init(
        id: UUID = UUID(),
        skillID: UUID,
        startedAt: Date,
        endedAt: Date,
        activeSeconds: Int,
        note: String = "",
        source: SessionSource = .timer,
        focusGoal: SessionFocusGoal? = nil,
        focusGoalCompleted: Bool = false
    ) {
        self.id = id
        self.skillID = skillID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = max(0, activeSeconds)
        self.note = note
        self.sourceRawValue = source.rawValue
        self.focusGoalKindRawValue = focusGoal?.kind.rawValue
        self.focusGoalTargetValue = focusGoal?.targetValue
        self.focusGoalStartingTotalXP = focusGoal?.startingTotalXP
        self.focusGoalCompletedRawValue = focusGoal == nil ? nil : focusGoalCompleted
    }

    var source: SessionSource {
        SessionSource(rawValue: sourceRawValue) ?? .timer
    }

    /// The calendar instant used for history, Quest, and achievement attribution.
    /// A session is credited when the effort was completed rather than when it began.
    var creditedAt: Date { endedAt }

    var recordedFocusGoal: SessionFocusGoal? {
        guard
            let rawKind = focusGoalKindRawValue,
            let kind = SessionFocusGoalKind(rawValue: rawKind),
            let targetValue = focusGoalTargetValue,
            let startingTotalXP = focusGoalStartingTotalXP
        else { return nil }

        return SessionFocusGoal(
            kind: kind,
            targetValue: targetValue,
            startingTotalXP: startingTotalXP
        )
    }

    var completedFocusGoal: Bool {
        focusGoalCompletedRawValue ?? false
    }
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

/// A frozen, period-bound challenge generated from the player's real Skillbook.
/// `currentValue` is a rebuildable cache; session history remains authoritative.
@Model
final class QuestAssignment {
    @Attribute(.unique) var id: String
    var templateID: String
    var cadenceRawValue: String
    var kindRawValue: String
    var slot: Int
    var periodStart: Date
    var periodEnd: Date
    var timeZoneIdentifier: String
    var title: String
    var questDescription: String
    var systemImage: String
    var targetSkillID: UUID?
    var targetSkillName: String?
    var targetPathRawValue: String?
    var targetValue: Int
    var baselineValue: Int
    var currentValue: Int
    var generatedAt: Date
    var completedAt: Date?
    var triggeringSessionID: UUID?
    var generationVersion: Int
    var retiredAt: Date?

    init(
        id: String,
        templateID: String,
        cadenceRawValue: String,
        kindRawValue: String,
        slot: Int,
        periodStart: Date,
        periodEnd: Date,
        timeZoneIdentifier: String,
        title: String,
        questDescription: String,
        systemImage: String,
        targetSkillID: UUID? = nil,
        targetSkillName: String? = nil,
        targetPathRawValue: String? = nil,
        targetValue: Int,
        baselineValue: Int = 0,
        currentValue: Int = 0,
        generatedAt: Date = .now,
        completedAt: Date? = nil,
        triggeringSessionID: UUID? = nil,
        generationVersion: Int = 1,
        retiredAt: Date? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.cadenceRawValue = cadenceRawValue
        self.kindRawValue = kindRawValue
        self.slot = slot
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.timeZoneIdentifier = timeZoneIdentifier
        self.title = title
        self.questDescription = questDescription
        self.systemImage = systemImage
        self.targetSkillID = targetSkillID
        self.targetSkillName = targetSkillName
        self.targetPathRawValue = targetPathRawValue
        self.targetValue = max(1, targetValue)
        self.baselineValue = max(0, baselineValue)
        self.currentValue = max(0, currentValue)
        self.generatedAt = generatedAt
        self.completedAt = completedAt
        self.triggeringSessionID = triggeringSessionID
        self.generationVersion = generationVersion
        self.retiredAt = retiredAt
    }
}

/// An effective-dated classification of a Skill into one Character Path.
/// The first assignment can explicitly backfill existing history. Later
/// assignments affect only sessions credited on or after `effectiveFrom`.
@Model
final class SkillPathAssignment {
    @Attribute(.unique) var id: String
    var skillID: UUID
    var pathRawValue: String
    var effectiveFrom: Date
    var createdAt: Date
    var isConfirmed: Bool

    init(
        id: String,
        skillID: UUID,
        pathRawValue: String,
        effectiveFrom: Date,
        createdAt: Date = .now,
        isConfirmed: Bool = false
    ) {
        self.id = id
        self.skillID = skillID
        self.pathRawValue = pathRawValue
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
        self.isConfirmed = isConfirmed
    }

    static func identifier(skillID: UUID, effectiveFrom: Date) -> String {
        let milliseconds = Int64((effectiveFrom.timeIntervalSince1970 * 1_000).rounded())
        return "path|\(skillID.uuidString.lowercased())|\(milliseconds)"
    }
}

/// Rebuildable Character Path aggregate. `SkillSession` and effective-dated
/// `SkillPathAssignment` records remain authoritative.
@Model
final class CharacterPathLedger {
    @Attribute(.unique) var pathRawValue: String
    var totalActiveSeconds: Int
    var sessionCount: Int
    var latestSessionAt: Date?
    var curveVersion: Int
    var rebuiltAt: Date

    init(
        pathRawValue: String,
        totalActiveSeconds: Int = 0,
        sessionCount: Int = 0,
        latestSessionAt: Date? = nil,
        curveVersion: Int = 1,
        rebuiltAt: Date = .now
    ) {
        self.pathRawValue = pathRawValue
        self.totalActiveSeconds = max(0, totalActiveSeconds)
        self.sessionCount = max(0, sessionCount)
        self.latestSessionAt = latestSessionAt
        self.curveVersion = curveVersion
        self.rebuiltAt = rebuiltAt
    }
}

/// The single local Character identity. Progression values are never stored
/// here because they are derived from authoritative completed sessions.
@Model
final class CharacterProfile {
    @Attribute(.unique) var id: String
    var displayName: String
    var crestSymbolName: String
    var accentHex: String
    var equippedTitleID: String?
    var pathReviewCompletedAt: Date?
    var progressionCurveVersion: Int
    var createdAt: Date

    init(
        id: String = "primary-character",
        displayName: String = "The Practitioner",
        crestSymbolName: String = "person.fill",
        accentHex: String = "D2A84A",
        equippedTitleID: String? = nil,
        pathReviewCompletedAt: Date? = nil,
        progressionCurveVersion: Int = 1,
        createdAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.crestSymbolName = crestSymbolName
        self.accentHex = accentHex
        self.equippedTitleID = equippedTitleID
        self.pathReviewCompletedAt = pathReviewCompletedAt
        self.progressionCurveVersion = progressionCurveVersion
        self.createdAt = createdAt
    }
}

/// Append-only evidence for an earned, equipable Character title.
@Model
final class CharacterTitleUnlock {
    @Attribute(.unique) var id: String
    var title: String
    var titleDescription: String
    var systemImage: String
    var sourceRawValue: String
    var pathRawValue: String?
    var skillID: UUID?
    var unlockedAt: Date
    var triggeringSessionID: UUID?

    init(
        id: String,
        title: String,
        titleDescription: String,
        systemImage: String,
        sourceRawValue: String,
        pathRawValue: String? = nil,
        skillID: UUID? = nil,
        unlockedAt: Date,
        triggeringSessionID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.titleDescription = titleDescription
        self.systemImage = systemImage
        self.sourceRawValue = sourceRawValue
        self.pathRawValue = pathRawValue
        self.skillID = skillID
        self.unlockedAt = unlockedAt
        self.triggeringSessionID = triggeringSessionID
    }
}

/// A player-selected Level 75 undertaking. Progress is rebuildable from
/// sessions while completion remains a permanent historical event.
@Model
final class ExpertChallenge {
    @Attribute(.unique) var id: UUID
    var skillID: UUID
    var kindRawValue: String
    var title: String
    var challengeDescription: String
    var systemImage: String
    var targetValue: Int
    var currentValue: Int
    var startedAt: Date
    var endsAt: Date
    var completedAt: Date?
    var triggeringSessionID: UUID?
    var retiredAt: Date?

    init(
        id: UUID = UUID(),
        skillID: UUID,
        kindRawValue: String,
        title: String,
        challengeDescription: String,
        systemImage: String,
        targetValue: Int,
        currentValue: Int = 0,
        startedAt: Date = .now,
        endsAt: Date,
        completedAt: Date? = nil,
        triggeringSessionID: UUID? = nil,
        retiredAt: Date? = nil
    ) {
        self.id = id
        self.skillID = skillID
        self.kindRawValue = kindRawValue
        self.title = title
        self.challengeDescription = challengeDescription
        self.systemImage = systemImage
        self.targetValue = max(1, targetValue)
        self.currentValue = max(0, currentValue)
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.completedAt = completedAt
        self.triggeringSessionID = triggeringSessionID
        self.retiredAt = retiredAt
    }
}

/// Identity-only Level 100 customization. Legacy never modifies XP, Quest
/// rewards, or the deterministic progression curve.
@Model
final class SkillLegacy {
    @Attribute(.unique) var skillID: UUID
    var masterTitle: String
    var crestSymbolName: String
    var chosenAt: Date

    init(
        skillID: UUID,
        masterTitle: String,
        crestSymbolName: String,
        chosenAt: Date = .now
    ) {
        self.skillID = skillID
        self.masterTitle = masterTitle
        self.crestSymbolName = crestSymbolName
        self.chosenAt = chosenAt
    }
}

/// Rebuildable calendar aggregates used by Today, Momentum, and records.
@Model
final class ActivityDayLedger {
    @Attribute(.unique) var id: String
    var dayStart: Date
    var timeZoneIdentifier: String
    var totalActiveSeconds: Int
    var xpEarned: Int
    var sessionCount: Int
    var distinctSkillCount: Int
    var longestSessionSeconds: Int
    var rebuiltAt: Date

    init(
        id: String,
        dayStart: Date,
        timeZoneIdentifier: String,
        totalActiveSeconds: Int = 0,
        xpEarned: Int = 0,
        sessionCount: Int = 0,
        distinctSkillCount: Int = 0,
        longestSessionSeconds: Int = 0,
        rebuiltAt: Date = .now
    ) {
        self.id = id
        self.dayStart = dayStart
        self.timeZoneIdentifier = timeZoneIdentifier
        self.totalActiveSeconds = max(0, totalActiveSeconds)
        self.xpEarned = max(0, xpEarned)
        self.sessionCount = max(0, sessionCount)
        self.distinctSkillCount = max(0, distinctSkillCount)
        self.longestSessionSeconds = max(0, longestSessionSeconds)
        self.rebuiltAt = rebuiltAt
    }
}

/// Append-only evidence that a committed session established a new personal best.
@Model
final class PersonalRecordEvent {
    @Attribute(.unique) var id: String
    var kindRawValue: String
    var skillID: UUID?
    var title: String
    var recordDescription: String
    var value: Int
    var previousValue: Int
    var achievedAt: Date
    var triggeringSessionID: UUID

    init(
        id: String,
        kindRawValue: String,
        skillID: UUID?,
        title: String,
        recordDescription: String,
        value: Int,
        previousValue: Int,
        achievedAt: Date,
        triggeringSessionID: UUID
    ) {
        self.id = id
        self.kindRawValue = kindRawValue
        self.skillID = skillID
        self.title = title
        self.recordDescription = recordDescription
        self.value = max(0, value)
        self.previousValue = max(0, previousValue)
        self.achievedAt = achievedAt
        self.triggeringSessionID = triggeringSessionID
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
