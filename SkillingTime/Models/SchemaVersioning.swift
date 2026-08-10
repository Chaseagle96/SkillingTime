import SwiftData

enum SkillingTimeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LifeSkill.self,
            SkillSession.self
        ]
    }
}

enum SkillingTimeSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            LifeSkill.self,
            SkillSession.self,
            AchievementUnlock.self,
            ChronicleUnlock.self
        ]
    }
}

enum SkillingTimeSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

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
}

enum SkillingTimeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SkillingTimeSchemaV1.self, SkillingTimeSchemaV2.self, SkillingTimeSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SkillingTimeSchemaV1.self,
        toVersion: SkillingTimeSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SkillingTimeSchemaV2.self,
        toVersion: SkillingTimeSchemaV3.self
    )
}
