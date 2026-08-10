import Foundation
import SwiftData

enum SkillCapability: String, Hashable, Sendable {
    case focusGoals
    case specialization

    var title: String {
        switch self {
        case .focusGoals: "Focus Goals"
        case .specialization: "Specialization"
        }
    }

    var description: String {
        switch self {
        case .focusGoals:
            "Set a duration, XP, or progression target before beginning this Skill."
        case .specialization:
            "Give this Skill a custom identity without changing its XP or progression."
        }
    }
}

struct SessionOutcome: Identifiable, Sendable {
    let id: UUID
    let skillID: UUID
    let skillName: String
    let symbolName: String
    let accentHex: String
    let durationSeconds: Int
    let xpEarned: Int
    let startingProgress: ProgressSnapshot
    let endingProgress: ProgressSnapshot
    let levelsCrossed: [Int]
    let chroniclesUnlocked: [ChronicleEntry]
    let achievementsUnlocked: [AchievementDefinition]
    let questsCompleted: [QuestStatus]
    let personalRecords: [PersonalRecordReveal]
    let capabilitiesUnlocked: [SkillCapability]
    let focusGoalResult: FocusGoalProgress?
    let note: String
    let wasAlreadyCommitted: Bool

    var levelsGained: Int {
        max(0, endingProgress.level - startingProgress.level)
    }
}

struct SessionMutationImpact: Sendable {
    let skillName: String
    let beforeDurationSeconds: Int
    let afterDurationSeconds: Int
    let beforeProgress: ProgressSnapshot
    let afterProgress: ProgressSnapshot
    let xpDelta: Int
    let rewardsAdded: [String]
    let rewardsPreserved: [String]
}

enum SessionCommitError: LocalizedError {
    case invalidDuration
    case skillNotFound
    case sessionIdentityConflict
    case unsupportedCurve(Int)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            "Choose a duration between one second and 48 hours."
        case .skillNotFound:
            "This Skill is no longer available."
        case .sessionIdentityConflict:
            "The recovered timer does not match this Skill. No history was changed."
        case .unsupportedCurve(let version):
            "This Skill uses unsupported progression curve version \(version)."
        case .persistence:
            "Skilling Time could not save this change. Your recoverable session has been preserved."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .persistence(let detail): detail
        default: nil
        }
    }
}

enum SessionCommitService {
    static let maximumSessionSeconds = 48 * 3600

    @MainActor
    static func commit(
        draft: CompletedSessionDraft,
        countedSeconds: Int,
        note: String,
        source: SessionSource,
        skill: LifeSkill,
        in modelContext: ModelContext,
        now: Date = .now
    ) throws -> SessionOutcome {
        try validate(durationSeconds: countedSeconds, skill: skill)
        guard draft.skillID == skill.id else {
            throw SessionCommitError.sessionIdentityConflict
        }

        do {
            let skills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
            let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
            let achievementRecords = try modelContext.fetch(FetchDescriptor<AchievementUnlock>())
            let chronicleRecords = try modelContext.fetch(FetchDescriptor<ChronicleUnlock>())
            let ledgers = try modelContext.fetch(FetchDescriptor<SkillLedger>())
            let dayLedgers = try modelContext.fetch(FetchDescriptor<ActivityDayLedger>())
            var questAssignments = try modelContext.fetch(FetchDescriptor<QuestAssignment>())
            let personalRecordEvents = try modelContext.fetch(
                FetchDescriptor<PersonalRecordEvent>()
            )
            let existingSession = sessions.first { $0.id == draft.id }
            if let existingSession, existingSession.skillID != skill.id {
                throw SessionCommitError.sessionIdentityConflict
            }
            let beforeSessions = sessions.filter { $0.id != draft.id }
            let previousRewardIdentifiers = Set(
                achievementRecords.map(\.id) + chronicleRecords.map(\.id)
            )
            QuestBoardService.ensureCurrentAssignments(
                assignments: &questAssignments,
                skills: skills,
                sessions: beforeSessions,
                in: modelContext,
                now: draft.endedAt
            )
            _ = QuestBoardService.reconcile(
                assignments: questAssignments,
                skills: skills,
                sessions: beforeSessions,
                triggeringSessionID: nil,
                now: now
            )

            let committedSession: SkillSession
            let wasAlreadyCommitted: Bool

            if let existingSession {
                committedSession = existingSession
                wasAlreadyCommitted = true
            } else {
                let safeNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                let adjustedStart = draft.endedAt.addingTimeInterval(TimeInterval(-countedSeconds))
                let beforeSkillSeconds = SessionAnalytics.totalSeconds(
                    for: skill.id,
                    sessions: beforeSessions
                )
                let liveTotalXP = ProgressionEngine.xp(
                    forActiveSeconds: beforeSkillSeconds + countedSeconds,
                    curveVersion: skill.progressionCurveVersion
                )
                let completedFocusGoal = draft.focusGoal.map {
                    FocusGoalProgress.evaluate(
                        goal: $0,
                        sessionSeconds: countedSeconds,
                        liveTotalXP: liveTotalXP
                    ).isComplete
                } ?? false
                let newSession = SkillSession(
                    id: draft.id,
                    skillID: skill.id,
                    startedAt: adjustedStart,
                    endedAt: draft.endedAt,
                    activeSeconds: countedSeconds,
                    note: safeNote,
                    source: source,
                    focusGoal: draft.focusGoal,
                    focusGoalCompleted: completedFocusGoal
                )
                modelContext.insert(newSession)
                committedSession = newSession
                wasAlreadyCommitted = false
            }

            let afterSessions = beforeSessions + [committedSession]
            let afterResolution = RewardResolver.resolve(skills: skills, sessions: afterSessions)
            _ = RewardRecordReconciler.reconcile(
                resolution: afterResolution,
                achievementRecords: achievementRecords,
                chronicleRecords: chronicleRecords,
                in: modelContext
            )
            SkillLedgerService.reconcile(
                skillID: skill.id,
                sessions: afterSessions,
                existingLedgers: ledgers,
                in: modelContext
            )
            ActivityDayLedgerService.reconcile(
                skills: skills,
                sessions: afterSessions,
                existingLedgers: dayLedgers,
                in: modelContext
            )
            let completedQuests = QuestBoardService.reconcile(
                assignments: questAssignments,
                skills: skills,
                sessions: afterSessions,
                triggeringSessionID: committedSession.id,
                now: now
            )
            let recordReveals = wasAlreadyCommitted ? [] : PersonalRecordEngine.newRecords(
                triggeringSession: committedSession,
                beforeSessions: beforeSessions,
                afterSessions: afterSessions,
                skills: skills
            )
            let newPersonalRecords = PersonalRecordReconciler.insertNew(
                recordReveals,
                existingRecords: personalRecordEvents,
                in: modelContext
            )
            try modelContext.save()

            return makeOutcome(
                session: committedSession,
                skill: skill,
                beforeSessions: beforeSessions,
                afterSessions: afterSessions,
                afterResolution: afterResolution,
                previousRewardIdentifiers: previousRewardIdentifiers,
                questsCompleted: completedQuests,
                personalRecords: newPersonalRecords,
                focusGoal: draft.focusGoal,
                wasAlreadyCommitted: wasAlreadyCommitted
            )
        } catch let error as SessionCommitError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw SessionCommitError.persistence(error.localizedDescription)
        }
    }

    static func previewUpdate(
        session: SkillSession,
        endedAt: Date,
        activeSeconds: Int,
        note: String,
        skills: [LifeSkill],
        sessions: [SkillSession],
        existingRewardIdentifiers: Set<String>? = nil
    ) throws -> SessionMutationImpact {
        guard let skill = skills.first(where: { $0.id == session.skillID }) else {
            throw SessionCommitError.skillNotFound
        }
        try validate(durationSeconds: activeSeconds, skill: skill)

        let replacement = SkillSession(
            id: session.id,
            skillID: session.skillID,
            startedAt: endedAt.addingTimeInterval(TimeInterval(-activeSeconds)),
            endedAt: endedAt,
            activeSeconds: activeSeconds,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            source: session.source
        )
        let candidateSessions = sessions.filter { $0.id != session.id } + [replacement]
        return mutationImpact(
            skill: skill,
            originalSession: session,
            beforeSessions: sessions,
            afterSessions: candidateSessions,
            skills: skills,
            existingRewardIdentifiers: existingRewardIdentifiers
        )
    }

    static func previewDeletion(
        session: SkillSession,
        skills: [LifeSkill],
        sessions: [SkillSession],
        existingRewardIdentifiers: Set<String>? = nil
    ) throws -> SessionMutationImpact {
        guard let skill = skills.first(where: { $0.id == session.skillID }) else {
            throw SessionCommitError.skillNotFound
        }
        return mutationImpact(
            skill: skill,
            originalSession: session,
            beforeSessions: sessions,
            afterSessions: sessions.filter { $0.id != session.id },
            skills: skills,
            existingRewardIdentifiers: existingRewardIdentifiers
        )
    }

    @MainActor
    static func update(
        session: SkillSession,
        endedAt: Date,
        activeSeconds: Int,
        note: String,
        in modelContext: ModelContext
    ) throws -> SessionMutationImpact {
        do {
            let skills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
            let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
            let achievementRecords = try modelContext.fetch(FetchDescriptor<AchievementUnlock>())
            let chronicleRecords = try modelContext.fetch(FetchDescriptor<ChronicleUnlock>())
            let ledgers = try modelContext.fetch(FetchDescriptor<SkillLedger>())
            let dayLedgers = try modelContext.fetch(FetchDescriptor<ActivityDayLedger>())
            let questAssignments = try modelContext.fetch(FetchDescriptor<QuestAssignment>())
            let existingRewardIdentifiers = Set(
                achievementRecords.map(\.id) + chronicleRecords.map(\.id)
            )
            let impact = try previewUpdate(
                session: session,
                endedAt: endedAt,
                activeSeconds: activeSeconds,
                note: note,
                skills: skills,
                sessions: sessions,
                existingRewardIdentifiers: existingRewardIdentifiers
            )

            session.endedAt = endedAt
            session.startedAt = endedAt.addingTimeInterval(TimeInterval(-activeSeconds))
            session.activeSeconds = activeSeconds
            session.note = note.trimmingCharacters(in: .whitespacesAndNewlines)

            if let focusGoal = session.recordedFocusGoal,
               let skill = skills.first(where: { $0.id == session.skillID }) {
                let skillSeconds = SessionAnalytics.totalSeconds(
                    for: session.skillID,
                    sessions: sessions
                )
                let totalXP = ProgressionEngine.xp(
                    forActiveSeconds: skillSeconds,
                    curveVersion: skill.progressionCurveVersion
                )
                session.focusGoalCompletedRawValue = FocusGoalProgress.evaluate(
                    goal: focusGoal,
                    sessionSeconds: activeSeconds,
                    liveTotalXP: totalXP
                ).isComplete
            }

            let resolution = RewardResolver.resolve(skills: skills, sessions: sessions)
            _ = RewardRecordReconciler.reconcile(
                resolution: resolution,
                achievementRecords: achievementRecords,
                chronicleRecords: chronicleRecords,
                in: modelContext
            )
            SkillLedgerService.reconcile(
                skillID: session.skillID,
                sessions: sessions,
                existingLedgers: ledgers,
                in: modelContext
            )
            ActivityDayLedgerService.reconcile(
                skills: skills,
                sessions: sessions,
                existingLedgers: dayLedgers,
                in: modelContext
            )
            _ = QuestBoardService.reconcile(
                assignments: questAssignments,
                skills: skills,
                sessions: sessions,
                triggeringSessionID: nil
            )
            try modelContext.save()
            return impact
        } catch let error as SessionCommitError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw SessionCommitError.persistence(error.localizedDescription)
        }
    }

    @MainActor
    static func delete(
        session: SkillSession,
        in modelContext: ModelContext
    ) throws -> SessionMutationImpact {
        do {
            let skills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
            let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
            let achievementRecords = try modelContext.fetch(FetchDescriptor<AchievementUnlock>())
            let chronicleRecords = try modelContext.fetch(FetchDescriptor<ChronicleUnlock>())
            let ledgers = try modelContext.fetch(FetchDescriptor<SkillLedger>())
            let dayLedgers = try modelContext.fetch(FetchDescriptor<ActivityDayLedger>())
            let questAssignments = try modelContext.fetch(FetchDescriptor<QuestAssignment>())
            let existingRewardIdentifiers = Set(
                achievementRecords.map(\.id) + chronicleRecords.map(\.id)
            )
            let impact = try previewDeletion(
                session: session,
                skills: skills,
                sessions: sessions,
                existingRewardIdentifiers: existingRewardIdentifiers
            )
            let remainingSessions = sessions.filter { $0.id != session.id }
            let resolution = RewardResolver.resolve(skills: skills, sessions: remainingSessions)

            modelContext.delete(session)
            _ = RewardRecordReconciler.reconcile(
                resolution: resolution,
                achievementRecords: achievementRecords,
                chronicleRecords: chronicleRecords,
                in: modelContext
            )
            SkillLedgerService.reconcile(
                skillID: session.skillID,
                sessions: remainingSessions,
                existingLedgers: ledgers,
                in: modelContext
            )
            ActivityDayLedgerService.reconcile(
                skills: skills,
                sessions: remainingSessions,
                existingLedgers: dayLedgers,
                in: modelContext
            )
            _ = QuestBoardService.reconcile(
                assignments: questAssignments,
                skills: skills,
                sessions: remainingSessions,
                triggeringSessionID: nil
            )
            try modelContext.save()
            return impact
        } catch let error as SessionCommitError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw SessionCommitError.persistence(error.localizedDescription)
        }
    }

    private static func validate(durationSeconds: Int, skill: LifeSkill) throws {
        guard (1...maximumSessionSeconds).contains(durationSeconds) else {
            throw SessionCommitError.invalidDuration
        }
        guard ProgressionEngine.isSupported(curveVersion: skill.progressionCurveVersion) else {
            throw SessionCommitError.unsupportedCurve(skill.progressionCurveVersion)
        }
    }

    private static func makeOutcome(
        session: SkillSession,
        skill: LifeSkill,
        beforeSessions: [SkillSession],
        afterSessions: [SkillSession],
        afterResolution: RewardResolution,
        previousRewardIdentifiers: Set<String>,
        questsCompleted: [QuestStatus],
        personalRecords: [PersonalRecordReveal],
        focusGoal: SessionFocusGoal?,
        wasAlreadyCommitted: Bool
    ) -> SessionOutcome {
        let beforeSeconds = SessionAnalytics.totalSeconds(for: skill.id, sessions: beforeSessions)
        let afterSeconds = SessionAnalytics.totalSeconds(for: skill.id, sessions: afterSessions)
        let beforeXP = ProgressionEngine.xp(
            forActiveSeconds: beforeSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        let afterXP = ProgressionEngine.xp(
            forActiveSeconds: afterSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        let beforeProgress = ProgressionEngine.progress(
            forTotalXP: beforeXP,
            curveVersion: skill.progressionCurveVersion
        )
        let afterProgress = ProgressionEngine.progress(
            forTotalXP: afterXP,
            curveVersion: skill.progressionCurveVersion
        )
        let newlyResolvedIDs = afterResolution.allIdentifiers
            .subtracting(previousRewardIdentifiers)

        let achievements = afterResolution.achievements
            .filter { newlyResolvedIDs.contains($0.id) }
            .compactMap { AchievementEngine.definition(id: $0.achievementID) }
        let chronicles = afterResolution.chronicles
            .filter { newlyResolvedIDs.contains($0.id) }
            .compactMap { ChronicleContent.entry(for: $0.milestoneLevel) }
        let capabilities = chronicles.compactMap { entry -> SkillCapability? in
            switch entry.level {
            case 25: .focusGoals
            case 50: .specialization
            default: nil
            }
        }
        let goalResult = focusGoal.map {
            FocusGoalProgress.evaluate(
                goal: $0,
                sessionSeconds: session.activeSeconds,
                liveTotalXP: afterXP
            )
        }

        return SessionOutcome(
            id: session.id,
            skillID: skill.id,
            skillName: skill.name,
            symbolName: skill.symbolName,
            accentHex: skill.accentHex,
            durationSeconds: session.activeSeconds,
            xpEarned: max(0, afterXP - beforeXP),
            startingProgress: beforeProgress,
            endingProgress: afterProgress,
            levelsCrossed: ProgressionEngine.levelsCrossed(
                fromXP: beforeXP,
                toXP: afterXP,
                curveVersion: skill.progressionCurveVersion
            ).map { Array($0) } ?? [],
            chroniclesUnlocked: wasAlreadyCommitted ? [] : chronicles,
            achievementsUnlocked: wasAlreadyCommitted ? [] : achievements,
            questsCompleted: wasAlreadyCommitted ? [] : questsCompleted,
            personalRecords: wasAlreadyCommitted ? [] : personalRecords,
            capabilitiesUnlocked: wasAlreadyCommitted ? [] : capabilities,
            focusGoalResult: goalResult,
            note: session.note,
            wasAlreadyCommitted: wasAlreadyCommitted
        )
    }

    private static func mutationImpact(
        skill: LifeSkill,
        originalSession: SkillSession,
        beforeSessions: [SkillSession],
        afterSessions: [SkillSession],
        skills: [LifeSkill],
        existingRewardIdentifiers: Set<String>?
    ) -> SessionMutationImpact {
        let beforeSeconds = SessionAnalytics.totalSeconds(for: skill.id, sessions: beforeSessions)
        let afterSeconds = SessionAnalytics.totalSeconds(for: skill.id, sessions: afterSessions)
        let beforeXP = ProgressionEngine.xp(
            forActiveSeconds: beforeSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        let afterXP = ProgressionEngine.xp(
            forActiveSeconds: afterSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        let beforeResolution = RewardResolver.resolve(skills: skills, sessions: beforeSessions)
        let afterResolution = RewardResolver.resolve(skills: skills, sessions: afterSessions)
        let baselineIdentifiers = existingRewardIdentifiers ?? beforeResolution.allIdentifiers
        let added = afterResolution.allIdentifiers.subtracting(baselineIdentifiers)
        let preserved = beforeResolution.allIdentifiers
            .subtracting(afterResolution.allIdentifiers)
            .intersection(baselineIdentifiers)

        return SessionMutationImpact(
            skillName: skill.name,
            beforeDurationSeconds: originalSession.activeSeconds,
            afterDurationSeconds: afterSessions.first(where: { $0.id == originalSession.id })?.activeSeconds ?? 0,
            beforeProgress: ProgressionEngine.progress(
                forTotalXP: beforeXP,
                curveVersion: skill.progressionCurveVersion
            ),
            afterProgress: ProgressionEngine.progress(
                forTotalXP: afterXP,
                curveVersion: skill.progressionCurveVersion
            ),
            xpDelta: afterXP - beforeXP,
            rewardsAdded: rewardNames(for: added, resolution: afterResolution),
            rewardsPreserved: rewardNames(for: preserved, resolution: beforeResolution)
        )
    }

    private static func rewardNames(
        for identifiers: Set<String>,
        resolution: RewardResolution
    ) -> [String] {
        let achievementNames = resolution.achievements
            .filter { identifiers.contains($0.id) }
            .compactMap { AchievementEngine.definition(id: $0.achievementID)?.title }
        let chronicleNames = resolution.chronicles
            .filter { identifiers.contains($0.id) }
            .compactMap { ChronicleContent.entry(for: $0.milestoneLevel)?.chapter }
        return (achievementNames + chronicleNames).sorted()
    }
}
