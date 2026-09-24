import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A complete, human-readable copy of everything that cannot be recomputed.
/// Ledgers (per-Skill, per-day) are derived and rebuilt after restore. Records of
/// retired systems (Quests, Paths, titles, Expert Challenges, Specializations,
/// Legacies) are still exported and restored so no history is ever lost.
struct SkillingTimeBackup: Codable, Equatable {
    static let currentFormatVersion = 1

    struct Skill: Codable, Equatable {
        let id: UUID
        let name: String
        let symbolName: String
        let accentHex: String
        let category: String
        let createdAt: Date
        let sortOrder: Int
        let isArchived: Bool
        let progressionCurveVersion: Int
    }

    struct Session: Codable, Equatable {
        let id: UUID
        let skillID: UUID
        let startedAt: Date
        let endedAt: Date
        let activeSeconds: Int
        let note: String
        let sourceRawValue: String
        let focusGoalKindRawValue: String?
        let focusGoalTargetValue: Int?
        let focusGoalStartingTotalXP: Int?
        let focusGoalCompletedRawValue: Bool?
    }

    struct Achievement: Codable, Equatable {
        let id: String
        let achievementID: String
        let skillID: UUID?
        let unlockedAt: Date
        let triggeringSessionID: UUID?
    }

    struct Chronicle: Codable, Equatable {
        let id: String
        let skillID: UUID
        let milestoneLevel: Int
        let unlockedAt: Date
        let triggeringSessionID: UUID
    }

    struct Specialization: Codable, Equatable {
        let skillID: UUID
        let title: String
        let chosenAt: Date
    }

    struct Quest: Codable, Equatable {
        let id: String
        let templateID: String
        let cadenceRawValue: String
        let kindRawValue: String
        let slot: Int
        let periodStart: Date
        let periodEnd: Date
        let timeZoneIdentifier: String
        let title: String
        let questDescription: String
        let systemImage: String
        let targetSkillID: UUID?
        let targetSkillName: String?
        let targetPathRawValue: String?
        let targetValue: Int
        let baselineValue: Int
        let currentValue: Int
        let generatedAt: Date
        let completedAt: Date?
        let triggeringSessionID: UUID?
        let generationVersion: Int
        let retiredAt: Date?
    }

    struct PathAssignment: Codable, Equatable {
        let id: String
        let skillID: UUID
        let pathRawValue: String
        let effectiveFrom: Date
        let createdAt: Date
        let isConfirmed: Bool
    }

    struct Profile: Codable, Equatable {
        let id: String
        let displayName: String
        let crestSymbolName: String
        let accentHex: String
        let equippedTitleID: String?
        let pathReviewCompletedAt: Date?
        let progressionCurveVersion: Int
        let createdAt: Date
    }

    struct Title: Codable, Equatable {
        let id: String
        let title: String
        let titleDescription: String
        let systemImage: String
        let sourceRawValue: String
        let pathRawValue: String?
        let skillID: UUID?
        let unlockedAt: Date
        let triggeringSessionID: UUID?
    }

    struct Challenge: Codable, Equatable {
        let id: UUID
        let skillID: UUID
        let kindRawValue: String
        let title: String
        let challengeDescription: String
        let systemImage: String
        let targetValue: Int
        let currentValue: Int
        let startedAt: Date
        let endsAt: Date
        let completedAt: Date?
        let triggeringSessionID: UUID?
        let retiredAt: Date?
    }

    struct Legacy: Codable, Equatable {
        let skillID: UUID
        let masterTitle: String
        let crestSymbolName: String
        let chosenAt: Date
    }

    struct Record: Codable, Equatable {
        let id: String
        let kindRawValue: String
        let skillID: UUID?
        let title: String
        let recordDescription: String
        let value: Int
        let previousValue: Int
        let achievedAt: Date
        let triggeringSessionID: UUID
    }

    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String?
    let skills: [Skill]
    let sessions: [Session]
    let achievements: [Achievement]
    let chronicles: [Chronicle]
    let specializations: [Specialization]
    let quests: [Quest]
    let pathAssignments: [PathAssignment]
    let profiles: [Profile]
    let titles: [Title]
    let challenges: [Challenge]
    let legacies: [Legacy]
    let records: [Record]
}

struct BackupRestoreSummary: Equatable {
    var skillsAdded = 0
    var skillsReplaced = 0
    var sessionsAdded = 0
    var otherRecordsAdded = 0
    var recordsAlreadyPresent = 0

    var message: String {
        var parts = [
            "\(sessionsAdded) \(sessionsAdded == 1 ? "session" : "sessions") and \(skillsAdded) \(skillsAdded == 1 ? "Skill" : "Skills") restored."
        ]
        if skillsReplaced > 0 {
            parts.append("\(skillsReplaced) empty starter \(skillsReplaced == 1 ? "Skill was" : "Skills were") replaced by the backed-up \(skillsReplaced == 1 ? "one" : "ones").")
        }
        if recordsAlreadyPresent > 0 {
            parts.append("\(recordsAlreadyPresent) \(recordsAlreadyPresent == 1 ? "record was" : "records were") already here and left unchanged.")
        }
        return parts.joined(separator: " ")
    }
}

enum BackupError: LocalizedError {
    case unsupportedFormat(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let version):
            "This backup was made by a newer version of Skilling Time (format \(version)). Update the app, then restore it."
        case .unreadable:
            "This file is not a Skilling Time backup, or it is damaged."
        }
    }
}

@MainActor
enum BackupService {
    static func makeBackup(in modelContext: ModelContext, now: Date = .now) throws -> SkillingTimeBackup {
        SkillingTimeBackup(
            formatVersion: SkillingTimeBackup.currentFormatVersion,
            exportedAt: now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            skills: try modelContext.fetch(FetchDescriptor<LifeSkill>()).map {
                .init(
                    id: $0.id, name: $0.name, symbolName: $0.symbolName, accentHex: $0.accentHex,
                    category: $0.category, createdAt: $0.createdAt, sortOrder: $0.sortOrder,
                    isArchived: $0.isArchived, progressionCurveVersion: $0.progressionCurveVersion
                )
            },
            sessions: try modelContext.fetch(FetchDescriptor<SkillSession>()).map {
                .init(
                    id: $0.id, skillID: $0.skillID, startedAt: $0.startedAt, endedAt: $0.endedAt,
                    activeSeconds: $0.activeSeconds, note: $0.note, sourceRawValue: $0.sourceRawValue,
                    focusGoalKindRawValue: $0.focusGoalKindRawValue,
                    focusGoalTargetValue: $0.focusGoalTargetValue,
                    focusGoalStartingTotalXP: $0.focusGoalStartingTotalXP,
                    focusGoalCompletedRawValue: $0.focusGoalCompletedRawValue
                )
            },
            achievements: try modelContext.fetch(FetchDescriptor<AchievementUnlock>()).map {
                .init(
                    id: $0.id, achievementID: $0.achievementID, skillID: $0.skillID,
                    unlockedAt: $0.unlockedAt, triggeringSessionID: $0.triggeringSessionID
                )
            },
            chronicles: try modelContext.fetch(FetchDescriptor<ChronicleUnlock>()).map {
                .init(
                    id: $0.id, skillID: $0.skillID, milestoneLevel: $0.milestoneLevel,
                    unlockedAt: $0.unlockedAt, triggeringSessionID: $0.triggeringSessionID
                )
            },
            specializations: try modelContext.fetch(FetchDescriptor<SkillSpecialization>()).map {
                .init(skillID: $0.skillID, title: $0.title, chosenAt: $0.chosenAt)
            },
            quests: try modelContext.fetch(FetchDescriptor<QuestAssignment>()).map {
                .init(
                    id: $0.id, templateID: $0.templateID, cadenceRawValue: $0.cadenceRawValue,
                    kindRawValue: $0.kindRawValue, slot: $0.slot, periodStart: $0.periodStart,
                    periodEnd: $0.periodEnd, timeZoneIdentifier: $0.timeZoneIdentifier,
                    title: $0.title, questDescription: $0.questDescription,
                    systemImage: $0.systemImage, targetSkillID: $0.targetSkillID,
                    targetSkillName: $0.targetSkillName, targetPathRawValue: $0.targetPathRawValue,
                    targetValue: $0.targetValue, baselineValue: $0.baselineValue,
                    currentValue: $0.currentValue, generatedAt: $0.generatedAt,
                    completedAt: $0.completedAt, triggeringSessionID: $0.triggeringSessionID,
                    generationVersion: $0.generationVersion, retiredAt: $0.retiredAt
                )
            },
            pathAssignments: try modelContext.fetch(FetchDescriptor<SkillPathAssignment>()).map {
                .init(
                    id: $0.id, skillID: $0.skillID, pathRawValue: $0.pathRawValue,
                    effectiveFrom: $0.effectiveFrom, createdAt: $0.createdAt, isConfirmed: $0.isConfirmed
                )
            },
            profiles: try modelContext.fetch(FetchDescriptor<CharacterProfile>()).map {
                .init(
                    id: $0.id, displayName: $0.displayName, crestSymbolName: $0.crestSymbolName,
                    accentHex: $0.accentHex, equippedTitleID: $0.equippedTitleID,
                    pathReviewCompletedAt: $0.pathReviewCompletedAt,
                    progressionCurveVersion: $0.progressionCurveVersion, createdAt: $0.createdAt
                )
            },
            titles: try modelContext.fetch(FetchDescriptor<CharacterTitleUnlock>()).map {
                .init(
                    id: $0.id, title: $0.title, titleDescription: $0.titleDescription,
                    systemImage: $0.systemImage, sourceRawValue: $0.sourceRawValue,
                    pathRawValue: $0.pathRawValue, skillID: $0.skillID,
                    unlockedAt: $0.unlockedAt, triggeringSessionID: $0.triggeringSessionID
                )
            },
            challenges: try modelContext.fetch(FetchDescriptor<ExpertChallenge>()).map {
                .init(
                    id: $0.id, skillID: $0.skillID, kindRawValue: $0.kindRawValue, title: $0.title,
                    challengeDescription: $0.challengeDescription, systemImage: $0.systemImage,
                    targetValue: $0.targetValue, currentValue: $0.currentValue,
                    startedAt: $0.startedAt, endsAt: $0.endsAt, completedAt: $0.completedAt,
                    triggeringSessionID: $0.triggeringSessionID, retiredAt: $0.retiredAt
                )
            },
            legacies: try modelContext.fetch(FetchDescriptor<SkillLegacy>()).map {
                .init(
                    skillID: $0.skillID, masterTitle: $0.masterTitle,
                    crestSymbolName: $0.crestSymbolName, chosenAt: $0.chosenAt
                )
            },
            records: try modelContext.fetch(FetchDescriptor<PersonalRecordEvent>()).map {
                .init(
                    id: $0.id, kindRawValue: $0.kindRawValue, skillID: $0.skillID, title: $0.title,
                    recordDescription: $0.recordDescription, value: $0.value,
                    previousValue: $0.previousValue, achievedAt: $0.achievedAt,
                    triggeringSessionID: $0.triggeringSessionID
                )
            }
        )
    }

    static func encode(_ backup: SkillingTimeBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> SkillingTimeBackup {
        struct Header: Decodable { let formatVersion: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw BackupError.unreadable
        }
        guard header.formatVersion <= SkillingTimeBackup.currentFormatVersion else {
            throw BackupError.unsupportedFormat(header.formatVersion)
        }
        do {
            return try decoder.decode(SkillingTimeBackup.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }

    /// Adds every record the store does not already have (matched by identifier),
    /// then rebuilds everything derived. Existing records are never overwritten,
    /// so restoring the same backup twice changes nothing the second time.
    @discardableResult
    static func restore(
        _ backup: SkillingTimeBackup,
        into modelContext: ModelContext
    ) throws -> BackupRestoreSummary {
        var summary = BackupRestoreSummary()
        do {
            let existingSkills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
            let existingSessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
            var skillIDs = Set(existingSkills.map(\.id))
            let sessionSkillIDs = Set(existingSessions.map(\.skillID))

            // A fresh install seeds starter Skills. An untouched starter with the same
            // name as a backed-up Skill is replaced instead of duplicated.
            for record in backup.skills where !skillIDs.contains(record.id) {
                if let placeholder = existingSkills.first(where: {
                    !sessionSkillIDs.contains($0.id)
                        && $0.name.compare(record.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                        && skillIDs.contains($0.id)
                }) {
                    try removeEmptySkill(placeholder, in: modelContext)
                    skillIDs.remove(placeholder.id)
                    summary.skillsReplaced += 1
                }
                modelContext.insert(
                    LifeSkill(
                        id: record.id, name: record.name, symbolName: record.symbolName,
                        accentHex: record.accentHex, category: record.category,
                        createdAt: record.createdAt, sortOrder: record.sortOrder,
                        isArchived: record.isArchived,
                        progressionCurveVersion: record.progressionCurveVersion
                    )
                )
                skillIDs.insert(record.id)
                summary.skillsAdded += 1
            }
            summary.recordsAlreadyPresent += backup.skills.count - summary.skillsAdded

            let sessionIDs = Set(existingSessions.map(\.id))
            for record in backup.sessions where !sessionIDs.contains(record.id) {
                let session = SkillSession(
                    id: record.id, skillID: record.skillID, startedAt: record.startedAt,
                    endedAt: record.endedAt, activeSeconds: record.activeSeconds, note: record.note
                )
                session.sourceRawValue = record.sourceRawValue
                session.focusGoalKindRawValue = record.focusGoalKindRawValue
                session.focusGoalTargetValue = record.focusGoalTargetValue
                session.focusGoalStartingTotalXP = record.focusGoalStartingTotalXP
                session.focusGoalCompletedRawValue = record.focusGoalCompletedRawValue
                modelContext.insert(session)
                summary.sessionsAdded += 1
            }
            summary.recordsAlreadyPresent += backup.sessions.count - summary.sessionsAdded

            func insertMissing<Model: PersistentModel, Record, Key: Hashable>(
                _ records: [Record],
                existing: [Model],
                modelKey: (Model) -> Key,
                recordKey: (Record) -> Key,
                make: (Record) -> Model
            ) {
                var known = Set(existing.map(modelKey))
                for record in records {
                    let key = recordKey(record)
                    guard !known.contains(key) else {
                        summary.recordsAlreadyPresent += 1
                        continue
                    }
                    modelContext.insert(make(record))
                    known.insert(key)
                    summary.otherRecordsAdded += 1
                }
            }

            insertMissing(
                backup.achievements,
                existing: try modelContext.fetch(FetchDescriptor<AchievementUnlock>()),
                modelKey: \.id, recordKey: \.id
            ) {
                AchievementUnlock(
                    id: $0.id, achievementID: $0.achievementID, skillID: $0.skillID,
                    unlockedAt: $0.unlockedAt, triggeringSessionID: $0.triggeringSessionID
                )
            }
            insertMissing(
                backup.chronicles,
                existing: try modelContext.fetch(FetchDescriptor<ChronicleUnlock>()),
                modelKey: \.id, recordKey: \.id
            ) {
                ChronicleUnlock(
                    id: $0.id, skillID: $0.skillID, milestoneLevel: $0.milestoneLevel,
                    unlockedAt: $0.unlockedAt, triggeringSessionID: $0.triggeringSessionID
                )
            }
            insertMissing(
                backup.specializations,
                existing: try modelContext.fetch(FetchDescriptor<SkillSpecialization>()),
                modelKey: \.skillID, recordKey: \.skillID
            ) {
                SkillSpecialization(skillID: $0.skillID, title: $0.title, chosenAt: $0.chosenAt)
            }
            insertMissing(
                backup.quests,
                existing: try modelContext.fetch(FetchDescriptor<QuestAssignment>()),
                modelKey: \.id, recordKey: \.id
            ) {
                QuestAssignment(
                    id: $0.id, templateID: $0.templateID, cadenceRawValue: $0.cadenceRawValue,
                    kindRawValue: $0.kindRawValue, slot: $0.slot, periodStart: $0.periodStart,
                    periodEnd: $0.periodEnd, timeZoneIdentifier: $0.timeZoneIdentifier,
                    title: $0.title, questDescription: $0.questDescription,
                    systemImage: $0.systemImage, targetSkillID: $0.targetSkillID,
                    targetSkillName: $0.targetSkillName, targetPathRawValue: $0.targetPathRawValue,
                    targetValue: $0.targetValue, baselineValue: $0.baselineValue,
                    currentValue: $0.currentValue, generatedAt: $0.generatedAt,
                    completedAt: $0.completedAt, triggeringSessionID: $0.triggeringSessionID,
                    generationVersion: $0.generationVersion, retiredAt: $0.retiredAt
                )
            }
            insertMissing(
                backup.pathAssignments,
                existing: try modelContext.fetch(FetchDescriptor<SkillPathAssignment>()),
                modelKey: \.id, recordKey: \.id
            ) {
                SkillPathAssignment(
                    id: $0.id, skillID: $0.skillID, pathRawValue: $0.pathRawValue,
                    effectiveFrom: $0.effectiveFrom, createdAt: $0.createdAt, isConfirmed: $0.isConfirmed
                )
            }
            // A fresh install creates a default profile before any restore. If it is
            // still untouched, take the backed-up identity instead of keeping it.
            let existingProfiles = try modelContext.fetch(FetchDescriptor<CharacterProfile>())
            for record in backup.profiles {
                guard let existing = existingProfiles.first(where: { $0.id == record.id }) else { continue }
                let isUntouchedDefault = existing.displayName == "The Practitioner"
                    && existing.crestSymbolName == "person.fill"
                    && existing.accentHex == "D2A84A"
                    && existing.equippedTitleID == nil
                    && existing.pathReviewCompletedAt == nil
                let alreadyMatches = existing.displayName == record.displayName
                    && existing.crestSymbolName == record.crestSymbolName
                    && existing.accentHex == record.accentHex
                    && existing.equippedTitleID == record.equippedTitleID
                    && existing.pathReviewCompletedAt == record.pathReviewCompletedAt
                guard isUntouchedDefault, !alreadyMatches else { continue }
                existing.displayName = record.displayName
                existing.crestSymbolName = record.crestSymbolName
                existing.accentHex = record.accentHex
                existing.equippedTitleID = record.equippedTitleID
                existing.pathReviewCompletedAt = record.pathReviewCompletedAt
                existing.createdAt = min(existing.createdAt, record.createdAt)
                summary.otherRecordsAdded += 1
                summary.recordsAlreadyPresent -= 1
            }
            insertMissing(
                backup.profiles,
                existing: existingProfiles,
                modelKey: \.id, recordKey: \.id
            ) {
                CharacterProfile(
                    id: $0.id, displayName: $0.displayName, crestSymbolName: $0.crestSymbolName,
                    accentHex: $0.accentHex, equippedTitleID: $0.equippedTitleID,
                    pathReviewCompletedAt: $0.pathReviewCompletedAt,
                    progressionCurveVersion: $0.progressionCurveVersion, createdAt: $0.createdAt
                )
            }
            insertMissing(
                backup.titles,
                existing: try modelContext.fetch(FetchDescriptor<CharacterTitleUnlock>()),
                modelKey: \.id, recordKey: \.id
            ) {
                CharacterTitleUnlock(
                    id: $0.id, title: $0.title, titleDescription: $0.titleDescription,
                    systemImage: $0.systemImage, sourceRawValue: $0.sourceRawValue,
                    pathRawValue: $0.pathRawValue, skillID: $0.skillID,
                    unlockedAt: $0.unlockedAt, triggeringSessionID: $0.triggeringSessionID
                )
            }
            insertMissing(
                backup.challenges,
                existing: try modelContext.fetch(FetchDescriptor<ExpertChallenge>()),
                modelKey: \.id, recordKey: \.id
            ) {
                ExpertChallenge(
                    id: $0.id, skillID: $0.skillID, kindRawValue: $0.kindRawValue, title: $0.title,
                    challengeDescription: $0.challengeDescription, systemImage: $0.systemImage,
                    targetValue: $0.targetValue, currentValue: $0.currentValue,
                    startedAt: $0.startedAt, endsAt: $0.endsAt, completedAt: $0.completedAt,
                    triggeringSessionID: $0.triggeringSessionID, retiredAt: $0.retiredAt
                )
            }
            insertMissing(
                backup.legacies,
                existing: try modelContext.fetch(FetchDescriptor<SkillLegacy>()),
                modelKey: \.skillID, recordKey: \.skillID
            ) {
                SkillLegacy(
                    skillID: $0.skillID, masterTitle: $0.masterTitle,
                    crestSymbolName: $0.crestSymbolName, chosenAt: $0.chosenAt
                )
            }
            insertMissing(
                backup.records,
                existing: try modelContext.fetch(FetchDescriptor<PersonalRecordEvent>()),
                modelKey: \.id, recordKey: \.id
            ) {
                PersonalRecordEvent(
                    id: $0.id, kindRawValue: $0.kindRawValue, skillID: $0.skillID, title: $0.title,
                    recordDescription: $0.recordDescription, value: $0.value,
                    previousValue: $0.previousValue, achievedAt: $0.achievedAt,
                    triggeringSessionID: $0.triggeringSessionID
                )
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        // Everything below is derived from what was just saved.
        try SkillLedgerService.rebuildAll(in: modelContext)
        try ActivityDayLedgerService.rebuildAll(in: modelContext)
        try RewardBackfillService.reconcileAll(in: modelContext)
        return summary
    }

    private static func removeEmptySkill(_ skill: LifeSkill, in modelContext: ModelContext) throws {
        let skillID = skill.id
        for assignment in try modelContext.fetch(FetchDescriptor<SkillPathAssignment>())
        where assignment.skillID == skillID {
            modelContext.delete(assignment)
        }
        for quest in try modelContext.fetch(FetchDescriptor<QuestAssignment>())
        where quest.targetSkillID == skillID && quest.retiredAt == nil {
            quest.retiredAt = .now
        }
        for ledger in try modelContext.fetch(FetchDescriptor<SkillLedger>())
        where ledger.skillID == skillID {
            modelContext.delete(ledger)
        }
        modelContext.delete(skill)
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.unreadable
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension JSONEncoder.DateEncodingStrategy {
    /// ISO 8601 with milliseconds, so restored dates keep sub-second order.
    static var iso8601WithFractionalSeconds: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(text)"
            )
        }
    }
}
