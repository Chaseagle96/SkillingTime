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
}

enum SkillingTimeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SkillingTimeSchemaV1.self,
            SkillingTimeSchemaV2.self,
            SkillingTimeSchemaV3.self,
            SkillingTimeSchemaV4.self
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
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
}
