import Foundation
import SwiftData

// Each released schema owns an immutable copy of its model declarations. Keeping
// historical types here prevents a future edit to the live models from silently
// changing the checksum SwiftData expects for an already-shipped store.
enum SkillingTimeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [LifeSkill.self, SkillSession.self] }

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
            progressionCurveVersion: Int = 1
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
            sourceRawValue: String = "timer"
        ) {
            self.id = id
            self.skillID = skillID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.activeSeconds = activeSeconds
            self.note = note
            self.sourceRawValue = sourceRawValue
        }
    }
}

enum SkillingTimeSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [LifeSkill.self, SkillSession.self, AchievementUnlock.self, ChronicleUnlock.self]
    }

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
            progressionCurveVersion: Int = 1
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
            sourceRawValue: String = "timer"
        ) {
            self.id = id
            self.skillID = skillID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.activeSeconds = activeSeconds
            self.note = note
            self.sourceRawValue = sourceRawValue
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
    }
}

enum SkillingTimeSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            LifeSkill.self,
            SkillSession.self,
            AchievementUnlock.self,
            ChronicleUnlock.self,
            SkillLedger.self,
            SkillSpecialization.self
        ]
    }

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
            progressionCurveVersion: Int = 1
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
            sourceRawValue: String = "timer"
        ) {
            self.id = id
            self.skillID = skillID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.activeSeconds = activeSeconds
            self.note = note
            self.sourceRawValue = sourceRawValue
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
    }

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
            self.totalActiveSeconds = totalActiveSeconds
            self.sessionCount = sessionCount
            self.longestSessionSeconds = longestSessionSeconds
            self.activeDayCount = activeDayCount
            self.firstSessionAt = firstSessionAt
            self.latestSessionAt = latestSessionAt
            self.rebuiltAt = rebuiltAt
        }
    }

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
}

enum SkillingTimeSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            LifeSkill.self,
            SkillSession.self,
            AchievementUnlock.self,
            ChronicleUnlock.self,
            SkillLedger.self,
            SkillSpecialization.self,
            QuestAssignment.self,
            ActivityDayLedger.self,
            PersonalRecordEvent.self
        ]
    }

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
            progressionCurveVersion: Int = 1
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
            sourceRawValue: String = "timer",
            focusGoalKindRawValue: String? = nil,
            focusGoalTargetValue: Int? = nil,
            focusGoalStartingTotalXP: Int? = nil,
            focusGoalCompletedRawValue: Bool? = nil
        ) {
            self.id = id
            self.skillID = skillID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.activeSeconds = activeSeconds
            self.note = note
            self.sourceRawValue = sourceRawValue
            self.focusGoalKindRawValue = focusGoalKindRawValue
            self.focusGoalTargetValue = focusGoalTargetValue
            self.focusGoalStartingTotalXP = focusGoalStartingTotalXP
            self.focusGoalCompletedRawValue = focusGoalCompletedRawValue
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
    }

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
            self.totalActiveSeconds = totalActiveSeconds
            self.sessionCount = sessionCount
            self.longestSessionSeconds = longestSessionSeconds
            self.activeDayCount = activeDayCount
            self.firstSessionAt = firstSessionAt
            self.latestSessionAt = latestSessionAt
            self.rebuiltAt = rebuiltAt
        }
    }

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
            self.targetValue = targetValue
            self.baselineValue = baselineValue
            self.currentValue = currentValue
            self.generatedAt = generatedAt
            self.completedAt = completedAt
            self.triggeringSessionID = triggeringSessionID
            self.generationVersion = generationVersion
            self.retiredAt = retiredAt
        }
    }

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
            self.totalActiveSeconds = totalActiveSeconds
            self.xpEarned = xpEarned
            self.sessionCount = sessionCount
            self.distinctSkillCount = distinctSkillCount
            self.longestSessionSeconds = longestSessionSeconds
            self.rebuiltAt = rebuiltAt
        }
    }

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
            self.value = value
            self.previousValue = previousValue
            self.achievedAt = achievedAt
            self.triggeringSessionID = triggeringSessionID
        }
    }
}

enum SkillingTimeSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            LifeSkill.self,
            SkillSession.self,
            AchievementUnlock.self,
            ChronicleUnlock.self,
            SkillLedger.self,
            SkillSpecialization.self,
            QuestAssignment.self,
            ActivityDayLedger.self,
            PersonalRecordEvent.self,
            SkillPathAssignment.self,
            CharacterPathLedger.self,
            CharacterProfile.self,
            CharacterTitleUnlock.self,
            ExpertChallenge.self,
            SkillLegacy.self
        ]
    }
}

enum SkillingTimeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SkillingTimeSchemaV1.self,
            SkillingTimeSchemaV2.self,
            SkillingTimeSchemaV3.self,
            SkillingTimeSchemaV4.self,
            SkillingTimeSchemaV5.self
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SkillingTimeSchemaV1.self,
        toVersion: SkillingTimeSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SkillingTimeSchemaV2.self,
        toVersion: SkillingTimeSchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SkillingTimeSchemaV3.self,
        toVersion: SkillingTimeSchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SkillingTimeSchemaV4.self,
        toVersion: SkillingTimeSchemaV5.self
    )
}
