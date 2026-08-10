import Foundation
import SwiftData
import XCTest
@testable import SkillingTime

final class ProgressionEngineTests: XCTestCase {
    private let curve = ProgressionCurveVersion.v1.rawValue

    func testTimeConvertsToXPDeterministically() {
        XCTAssertEqual(ProgressionEngine.xp(forActiveSeconds: 0, curveVersion: curve), 0)
        XCTAssertEqual(ProgressionEngine.xp(forActiveSeconds: 2, curveVersion: curve), 0)
        XCTAssertEqual(ProgressionEngine.xp(forActiveSeconds: 3, curveVersion: curve), 1)
        XCTAssertEqual(ProgressionEngine.xp(forActiveSeconds: 60, curveVersion: curve), 20)
        XCTAssertEqual(ProgressionEngine.xp(forActiveSeconds: 3_600, curveVersion: curve), 1_200)
    }

    func testPublishedVersionOneThresholdsRemainStable() {
        XCTAssertEqual(ProgressionEngine.cumulativeXP(toReach: 2, curveVersion: curve), 115)
        XCTAssertEqual(ProgressionEngine.cumulativeXP(toReach: 5, curveVersion: curve), 578)
        XCTAssertEqual(ProgressionEngine.cumulativeXP(toReach: 10, curveVersion: curve), 1_755)
        XCTAssertEqual(ProgressionEngine.cumulativeXP(toReach: 25, curveVersion: curve), 8_668)
        XCTAssertEqual(ProgressionEngine.cumulativeXP(toReach: 50, curveVersion: curve), 35_363)
        XCTAssertEqual(ProgressionEngine.cumulativeXP(toReach: 75, curveVersion: curve), 97_134)
        XCTAssertEqual(ProgressionEngine.cumulativeXP(toReach: 100, curveVersion: curve), 245_531)
    }

    func testExactLevelBoundary() {
        let threshold = ProgressionEngine.cumulativeXP(toReach: 25, curveVersion: curve)
        XCTAssertEqual(
            ProgressionEngine.level(forTotalXP: threshold - 1, curveVersion: curve),
            24
        )
        XCTAssertEqual(
            ProgressionEngine.level(forTotalXP: threshold, curveVersion: curve),
            25
        )
        XCTAssertEqual(ProgressionEngine.rank(for: 25), .apprentice)
    }

    func testCurveAlwaysGetsHarder() {
        for level in 2..<ProgressionEngine.maximumLevel(curveVersion: curve) {
            XCTAssertGreaterThan(
                ProgressionEngine.xpToAdvance(from: level, curveVersion: curve),
                ProgressionEngine.xpToAdvance(from: level - 1, curveVersion: curve)
            )
        }
    }

    func testMultipleMilestonesAndLevelsArePreserved() {
        let before = ProgressionEngine.cumulativeXP(toReach: 24, curveVersion: curve)
        let after = ProgressionEngine.cumulativeXP(toReach: 76, curveVersion: curve)
        XCTAssertEqual(
            ProgressionEngine.milestonesCrossed(
                fromXP: before,
                toXP: after,
                curveVersion: curve
            ),
            [25, 50, 75]
        )
        XCTAssertEqual(
            ProgressionEngine.levelsCrossed(
                fromXP: before,
                toXP: after,
                curveVersion: curve
            ),
            25...76
        )
    }

    func testMasteryStarsBeginBeyondLevelOneHundred() {
        let levelCap = ProgressionEngine.cumulativeXP(toReach: 100, curveVersion: curve)
        let starXP = ProgressionEngine.masteryXPPerStar(curveVersion: curve)
        let progress = ProgressionEngine.progress(
            forTotalXP: levelCap + (3 * starXP) + 42,
            curveVersion: curve
        )
        XCTAssertEqual(progress.level, 100)
        XCTAssertEqual(progress.masteryStars, 3)
        XCTAssertEqual(progress.currentLevelXP, 42)
        XCTAssertEqual(progress.rank, .master)
    }

    func testUnknownCurveIsRejectedBeforeProgressionWork() {
        XCTAssertTrue(ProgressionEngine.isSupported(curveVersion: curve))
        XCTAssertFalse(ProgressionEngine.isSupported(curveVersion: 999))
    }

    func testAchievementCatalogStartsWithSixtyOneTypes() {
        XCTAssertEqual(AchievementEngine.skillDefinitions.count, 46)
        XCTAssertEqual(AchievementEngine.globalDefinitions.count, 15)
        XCTAssertEqual(AchievementEngine.achievementTypeCount, 61)
    }
}

final class SessionControllerTests: XCTestCase {
    @MainActor
    func testFinishFreezesChronologyUntilCommitSucceeds() {
        let suiteName = "SessionControllerTests.finish"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = SessionController(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000)
        let skillID = UUID()

        XCTAssertTrue(controller.start(skillID: skillID, at: start))
        controller.pause(at: start.addingTimeInterval(120))
        controller.resume(at: start.addingTimeInterval(900))

        let firstDraft = controller.requestFinish(at: start.addingTimeInterval(960))
        let retryDraft = controller.requestFinish(at: start.addingTimeInterval(1_260))

        XCTAssertEqual(firstDraft?.activeSeconds, 180)
        XCTAssertEqual(retryDraft?.activeSeconds, 180)
        XCTAssertEqual(firstDraft?.endedAt, start.addingTimeInterval(960))
        XCTAssertEqual(retryDraft?.endedAt, firstDraft?.endedAt)
        XCTAssertNotNil(controller.activeSession, "A pending timer stays recoverable before save.")

        controller.markCommitted(sessionID: firstDraft!.id)
        XCTAssertNil(controller.activeSession)
    }

    @MainActor
    func testActiveSessionAndFocusGoalRestoreFromDefaults() {
        let suiteName = "SessionControllerTests.restore"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = Date(timeIntervalSince1970: 2_000)
        let skillID = UUID()
        let goal = SessionFocusGoal.duration(seconds: 1_800, startingTotalXP: 400)
        let first = SessionController(defaults: defaults)
        XCTAssertTrue(first.start(skillID: skillID, focusGoal: goal, at: start))

        let restored = SessionController(defaults: defaults)
        XCTAssertEqual(restored.activeSession?.skillID, skillID)
        XCTAssertEqual(restored.activeSession?.startedAt, start)
        XCTAssertEqual(restored.activeSession?.focusGoal, goal)
    }

    @MainActor
    func testPendingFinishRestoresWithoutMovingItsEndDate() throws {
        let suiteName = "SessionControllerTests.pending-finish"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = Date(timeIntervalSince1970: 3_000)
        let finish = start.addingTimeInterval(425)
        let first = SessionController(defaults: defaults)
        XCTAssertTrue(first.start(skillID: UUID(), at: start))
        let originalDraft = try XCTUnwrap(first.requestFinish(at: finish))

        let restored = SessionController(defaults: defaults)
        let restoredDraft = try XCTUnwrap(
            restored.requestFinish(at: finish.addingTimeInterval(600))
        )

        XCTAssertTrue(restored.activeSession?.isAwaitingCommit == true)
        XCTAssertEqual(restoredDraft.endedAt, finish)
        XCTAssertEqual(restoredDraft.activeSeconds, 425)
        XCTAssertEqual(restoredDraft, originalDraft)
    }

    @MainActor
    func testControllerAcceptsPauseAndResumeFromSharedStore() throws {
        let suiteName = "SessionControllerTests.shared-actions"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let start = Date(timeIntervalSince1970: 4_000)
        let controller = SessionController(defaults: defaults)
        XCTAssertTrue(controller.start(skillID: UUID(), at: start))
        let sessionID = try XCTUnwrap(controller.activeSession?.id)

        _ = try XCTUnwrap(
            SharedActiveSessionStore.togglePause(
                sessionID: sessionID,
                at: start.addingTimeInterval(90),
                defaults: defaults
            )
        )
        controller.refreshFromSharedStorage()
        XCTAssertTrue(controller.activeSession?.isPaused == true)
        XCTAssertEqual(controller.activeSession?.accumulatedActiveSeconds, 90)

        _ = try XCTUnwrap(
            SharedActiveSessionStore.togglePause(
                sessionID: sessionID,
                at: start.addingTimeInterval(150),
                defaults: defaults
            )
        )
        controller.refreshFromSharedStorage()
        XCTAssertFalse(controller.activeSession?.isPaused ?? true)
        XCTAssertEqual(
            controller.activeSession?.activeSegmentStartedAt,
            start.addingTimeInterval(150)
        )
    }
}

final class FocusGoalTests: XCTestCase {
    func testDurationGoalCompletesAtTarget() {
        let goal = SessionFocusGoal.duration(seconds: 1_800, startingTotalXP: 200)
        let progress = FocusGoalProgress.evaluate(
            goal: goal,
            sessionSeconds: 1_800,
            liveTotalXP: 500
        )

        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.fractionComplete, 1)
    }

    func testProgressionGoalMeasuresFromStartingXP() {
        let goal = SessionFocusGoal.progression(targetTotalXP: 1_200, startingTotalXP: 1_000)
        let progress = FocusGoalProgress.evaluate(
            goal: goal,
            sessionSeconds: 60,
            liveTotalXP: 1_100
        )

        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.currentValue, 100)
        XCTAssertEqual(progress.targetValue, 200)
        XCTAssertEqual(progress.fractionComplete, 0.5)
    }
}

final class HistoryAttributionTests: XCTestCase {
    func testCrossMidnightSessionIsCreditedWhenItEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let skillID = UUID()
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 23, minute: 50))
        )
        let end = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 0, minute: 10))
        )
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 12))
        )
        let session = SkillSession(
            skillID: skillID,
            startedAt: start,
            endedAt: end,
            activeSeconds: 1_200
        )

        let period = QuestEngine.period(for: .daily, calendar: calendar, containing: now)
        let assignment = QuestAssignment(
            id: "daily-attribution",
            templateID: "daily-put-in-time",
            cadenceRawValue: QuestCadence.daily.rawValue,
            kindRawValue: QuestKind.activeTime.rawValue,
            slot: 0,
            periodStart: period.start,
            periodEnd: period.end,
            timeZoneIdentifier: calendar.timeZone.identifier,
            title: "Put in the Time",
            questDescription: "Skill today.",
            systemImage: "hourglass",
            targetValue: 1_200
        )
        assignment.currentValue = QuestEngine.currentValue(
            for: assignment,
            skills: [],
            sessions: [session]
        )
        let daily = try XCTUnwrap(QuestEngine.status(assignment))

        XCTAssertEqual(daily.currentValue, 1_200)
        XCTAssertTrue(daily.isComplete)
    }

    func testRetiredSkillsRemainInLifetimeTotalLevel() {
        let active = LifeSkill(name: "Cooking", symbolName: "fork.knife", accentHex: "FFFFFF", category: "Home")
        let retired = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning",
            isArchived: true
        )

        XCTAssertEqual(SessionAnalytics.totalLevel(skills: [active, retired], sessions: []), 2)
    }
}

final class RewardResolverTests: XCTestCase {
    func testChronicleUnlockUsesTriggeringSessionEndDate() {
        let curve = ProgressionCurveVersion.v1.rawValue
        let skill = LifeSkill(
            name: "Cooking",
            symbolName: "fork.knife",
            accentHex: "FFFFFF",
            category: "Home",
            progressionCurveVersion: curve
        )
        let thresholdXP = ProgressionEngine.cumulativeXP(toReach: 25, curveVersion: curve)
        let endedAt = Date(timeIntervalSince1970: 50_000)
        let session = SkillSession(
            skillID: skill.id,
            startedAt: endedAt.addingTimeInterval(TimeInterval(-(thresholdXP * 3))),
            endedAt: endedAt,
            activeSeconds: thresholdXP * 3
        )

        let resolution = RewardResolver.resolve(skills: [skill], sessions: [session])
        let unlock = resolution.chronicles.first { $0.milestoneLevel == 25 }

        XCTAssertEqual(unlock?.unlockedAt, endedAt)
        XCTAssertEqual(unlock?.triggeringSessionID, session.id)
    }
}

final class SessionCommitServiceTests: XCTestCase {
    @MainActor
    func testCommitKeepsFrozenEndDateAndPersistsRewardRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Cooking",
            symbolName: "fork.knife",
            accentHex: "FFFFFF",
            category: "Home"
        )
        context.insert(skill)
        try context.save()

        let thresholdXP = ProgressionEngine.cumulativeXP(
            toReach: 25,
            curveVersion: skill.progressionCurveVersion
        )
        let endedAt = Date(timeIntervalSince1970: 100_000)
        let draft = CompletedSessionDraft(
            id: UUID(),
            skillID: skill.id,
            startedAt: endedAt.addingTimeInterval(TimeInterval(-(thresholdXP * 3))),
            endedAt: endedAt,
            activeSeconds: thresholdXP * 3,
            focusGoal: nil,
            shouldResumeOnCancel: false
        )

        let outcome = try SessionCommitService.commit(
            draft: draft,
            countedSeconds: draft.activeSeconds,
            note: "Milestone session",
            source: .timer,
            skill: skill,
            in: context,
            now: endedAt.addingTimeInterval(600)
        )

        let sessions = try context.fetch(FetchDescriptor<SkillSession>())
        let chronicles = try context.fetch(FetchDescriptor<ChronicleUnlock>())
        let achievements = try context.fetch(FetchDescriptor<AchievementUnlock>())
        let ledgers = try context.fetch(FetchDescriptor<SkillLedger>())

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.endedAt, endedAt)
        XCTAssertEqual(sessions.first?.startedAt, endedAt.addingTimeInterval(TimeInterval(-draft.activeSeconds)))
        XCTAssertEqual(chronicles.first { $0.milestoneLevel == 25 }?.unlockedAt, endedAt)
        XCTAssertFalse(achievements.isEmpty)
        XCTAssertEqual(outcome.endingProgress.level, 25)
        XCTAssertTrue(outcome.capabilitiesUnlocked.contains(.focusGoals))
        XCTAssertEqual(ledgers.first?.totalActiveSeconds, draft.activeSeconds)
        XCTAssertEqual(ledgers.first?.sessionCount, 1)
    }

    @MainActor
    func testCommitIsIdempotentByRecoveredTimerUUID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning"
        )
        context.insert(skill)
        try context.save()

        let endedAt = Date(timeIntervalSince1970: 200_000)
        let draft = CompletedSessionDraft(
            id: UUID(),
            skillID: skill.id,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            activeSeconds: 600,
            focusGoal: nil,
            shouldResumeOnCancel: false
        )

        _ = try SessionCommitService.commit(
            draft: draft,
            countedSeconds: 600,
            note: "First save",
            source: .timer,
            skill: skill,
            in: context,
            now: endedAt
        )
        let retry = try SessionCommitService.commit(
            draft: draft,
            countedSeconds: 900,
            note: "Retry",
            source: .timer,
            skill: skill,
            in: context,
            now: endedAt.addingTimeInterval(300)
        )

        let sessions = try context.fetch(FetchDescriptor<SkillSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.activeSeconds, 600)
        XCTAssertTrue(retry.wasAlreadyCommitted)
    }

    @MainActor
    func testSessionCorrectionReconcilesLedgerInTheSameSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning"
        )
        context.insert(skill)
        try context.save()

        let endedAt = Date(timeIntervalSince1970: 250_000)
        let draft = CompletedSessionDraft(
            id: UUID(),
            skillID: skill.id,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            activeSeconds: 600,
            focusGoal: nil,
            shouldResumeOnCancel: false
        )
        _ = try SessionCommitService.commit(
            draft: draft,
            countedSeconds: 600,
            note: "Original",
            source: .timer,
            skill: skill,
            in: context,
            now: endedAt
        )

        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<SkillSession>()).first
        )
        _ = try SessionCommitService.update(
            session: session,
            endedAt: endedAt,
            activeSeconds: 900,
            note: "Corrected",
            in: context
        )

        let ledger = try XCTUnwrap(
            context.fetch(FetchDescriptor<SkillLedger>()).first
        )
        XCTAssertEqual(ledger.totalActiveSeconds, 900)
        XCTAssertEqual(ledger.sessionCount, 1)
        XCTAssertEqual(ledger.longestSessionSeconds, 900)
        XCTAssertEqual(session.note, "Corrected")
    }

    @MainActor
    func testEarnedRewardsSurviveDeletingTheirTriggeringSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Cooking",
            symbolName: "fork.knife",
            accentHex: "FFFFFF",
            category: "Home"
        )
        context.insert(skill)
        try context.save()

        let thresholdXP = ProgressionEngine.cumulativeXP(
            toReach: 25,
            curveVersion: skill.progressionCurveVersion
        )
        let endedAt = Date(timeIntervalSince1970: 300_000)
        let draft = CompletedSessionDraft(
            id: UUID(),
            skillID: skill.id,
            startedAt: endedAt.addingTimeInterval(TimeInterval(-(thresholdXP * 3))),
            endedAt: endedAt,
            activeSeconds: thresholdXP * 3,
            focusGoal: nil,
            shouldResumeOnCancel: false
        )
        _ = try SessionCommitService.commit(
            draft: draft,
            countedSeconds: draft.activeSeconds,
            note: "Earn Apprentice",
            source: .timer,
            skill: skill,
            in: context,
            now: endedAt
        )

        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<SkillSession>()).first
        )
        let impact = try SessionCommitService.delete(session: session, in: context)
        let remainingSessions = try context.fetch(FetchDescriptor<SkillSession>())
        let remainingChronicles = try context.fetch(FetchDescriptor<ChronicleUnlock>())
        let remainingLedgers = try context.fetch(FetchDescriptor<SkillLedger>())

        XCTAssertTrue(remainingSessions.isEmpty)
        XCTAssertNotNil(remainingChronicles.first { $0.milestoneLevel == 25 })
        XCTAssertTrue(impact.rewardsPreserved.contains("I · Familiar Hands"))
        XCTAssertEqual(
            SessionAnalytics.totalLevel(skills: [skill], sessions: remainingSessions),
            1
        )
        XCTAssertTrue(remainingLedgers.isEmpty)
    }

    @MainActor
    func testJourneymanCommitUnlocksSpecializationCapability() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Cooking",
            symbolName: "fork.knife",
            accentHex: "FFFFFF",
            category: "Home"
        )
        context.insert(skill)
        try context.save()

        let thresholdXP = ProgressionEngine.cumulativeXP(
            toReach: 50,
            curveVersion: skill.progressionCurveVersion
        )
        let endedAt = Date(timeIntervalSince1970: 400_000)
        let duration = thresholdXP * ProgressionEngine.secondsPerXP(
            curveVersion: skill.progressionCurveVersion
        )
        let draft = CompletedSessionDraft(
            id: UUID(),
            skillID: skill.id,
            startedAt: endedAt.addingTimeInterval(TimeInterval(-duration)),
            endedAt: endedAt,
            activeSeconds: duration,
            focusGoal: nil,
            shouldResumeOnCancel: false
        )

        let outcome = try SessionCommitService.commit(
            draft: draft,
            countedSeconds: duration,
            note: "Journeyman session",
            source: .timer,
            skill: skill,
            in: context,
            now: endedAt
        )

        XCTAssertEqual(outcome.endingProgress.level, 50)
        XCTAssertTrue(outcome.capabilitiesUnlocked.contains(.focusGoals))
        XCTAssertTrue(outcome.capabilitiesUnlocked.contains(.specialization))
        XCTAssertEqual(
            Set(outcome.chroniclesUnlocked.map(\.level)),
            Set([25, 50])
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
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
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

final class SkillLedgerServiceTests: XCTestCase {
    @MainActor
    func testRebuildProducesExactAggregatesAndRemovesStaleRows() throws {
        let schema = Schema([
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
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let skillID = UUID()
        let staleSkillID = UUID()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let firstEnd = Date(timeIntervalSince1970: 100_000)
        let secondEnd = firstEnd.addingTimeInterval(86_400)

        context.insert(
            SkillSession(
                skillID: skillID,
                startedAt: firstEnd.addingTimeInterval(-600),
                endedAt: firstEnd,
                activeSeconds: 600
            )
        )
        context.insert(
            SkillSession(
                skillID: skillID,
                startedAt: secondEnd.addingTimeInterval(-1_800),
                endedAt: secondEnd,
                activeSeconds: 1_800
            )
        )
        context.insert(SkillLedger(skillID: staleSkillID, totalActiveSeconds: 999))
        try context.save()

        let rebuiltAt = Date(timeIntervalSince1970: 300_000)
        XCTAssertTrue(
            try SkillLedgerService.rebuildIfNeeded(
                in: context,
                calendar: calendar,
                now: rebuiltAt
            )
        )

        let ledgers = try context.fetch(FetchDescriptor<SkillLedger>())
        let ledger = try XCTUnwrap(ledgers.first { $0.skillID == skillID })
        XCTAssertEqual(ledgers.count, 1)
        XCTAssertEqual(ledger.totalActiveSeconds, 2_400)
        XCTAssertEqual(ledger.sessionCount, 2)
        XCTAssertEqual(ledger.longestSessionSeconds, 1_800)
        XCTAssertEqual(ledger.activeDayCount, 2)
        XCTAssertEqual(ledger.firstSessionAt, firstEnd)
        XCTAssertEqual(ledger.latestSessionAt, secondEnd)
        XCTAssertEqual(ledger.rebuiltAt, rebuiltAt)

        let index = SessionAnalytics.index(ledgers: ledgers)
        XCTAssertEqual(index.statistics(for: skillID).averageSeconds, 1_200)
        XCTAssertEqual(index.totalSeconds, 2_400)

        XCTAssertFalse(
            try SkillLedgerService.rebuildIfNeeded(
                in: context,
                calendar: calendar,
                now: rebuiltAt.addingTimeInterval(100)
            )
        )
        XCTAssertEqual(ledger.rebuiltAt, rebuiltAt)
    }
}

final class QuestboardV4Tests: XCTestCase {
    func testGenerationIsDeterministicAndDoesNotRerollExistingPeriod() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))
        )
        let skills = [
            LifeSkill(name: "Cooking", symbolName: "fork.knife", accentHex: "FFFFFF", category: "Home"),
            LifeSkill(name: "Reading", symbolName: "book", accentHex: "FFFFFF", category: "Learning"),
            LifeSkill(name: "Exercise", symbolName: "figure.run", accentHex: "FFFFFF", category: "Wellbeing")
        ]

        let first = QuestEngine.makeAssignments(
            cadence: .daily,
            skills: skills,
            sessions: [],
            existingAssignments: [],
            calendar: calendar,
            now: now
        )
        let repeated = QuestEngine.makeAssignments(
            cadence: .daily,
            skills: skills,
            sessions: [],
            existingAssignments: first,
            calendar: calendar,
            now: now
        )
        let independentlyGenerated = QuestEngine.makeAssignments(
            cadence: .daily,
            skills: skills,
            sessions: [],
            existingAssignments: [],
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.templateID), independentlyGenerated.map(\.templateID))
        XCTAssertEqual(first.first?.templateID, "daily-put-in-time")
        XCTAssertTrue(repeated.isEmpty)
    }

    func testIneligibleQuestTypesAreNotGenerated() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let skills = [
            LifeSkill(name: "Cooking", symbolName: "fork.knife", accentHex: "FFFFFF", category: "Home", createdAt: now),
            LifeSkill(name: "Reading", symbolName: "book", accentHex: "FFFFFF", category: "Learning", createdAt: now)
        ]

        let daily = QuestEngine.makeAssignments(
            cadence: .daily,
            skills: skills,
            sessions: [],
            existingAssignments: [],
            now: now
        )
        let weekly = QuestEngine.makeAssignments(
            cadence: .weekly,
            skills: skills,
            sessions: [],
            existingAssignments: [],
            now: now
        )
        let identifiers = Set((daily + weekly).map(\.templateID))

        XCTAssertFalse(identifiers.contains("daily-diversify"))
        XCTAssertFalse(identifiers.contains("daily-old-friend"))
        XCTAssertFalse(identifiers.contains("daily-finish-focus"))
        XCTAssertFalse(identifiers.contains("weekly-journeyman-work"))
    }

    @MainActor
    func testCompletedQuestRemainsEarnedAfterSessionCorrection() throws {
        let container = try makeV4Container()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning"
        )
        context.insert(skill)
        try context.save()

        let endedAt = Date.now
        let draft = CompletedSessionDraft(
            id: UUID(),
            skillID: skill.id,
            startedAt: endedAt.addingTimeInterval(-3_600),
            endedAt: endedAt,
            activeSeconds: 3_600,
            focusGoal: nil,
            shouldResumeOnCancel: false
        )
        let outcome = try SessionCommitService.commit(
            draft: draft,
            countedSeconds: 3_600,
            note: "Deep reading",
            source: .timer,
            skill: skill,
            in: context,
            now: endedAt
        )
        XCTAssertFalse(outcome.questsCompleted.isEmpty)

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<SkillSession>()).first)
        let completedBefore = try XCTUnwrap(
            context.fetch(FetchDescriptor<QuestAssignment>()).first {
                $0.completedAt != nil
            }
        )
        _ = try SessionCommitService.update(
            session: session,
            endedAt: endedAt,
            activeSeconds: 60,
            note: "Corrected",
            in: context
        )

        let assignment = try XCTUnwrap(
            context.fetch(FetchDescriptor<QuestAssignment>()).first {
                $0.id == completedBefore.id
            }
        )
        XCTAssertNotNil(assignment.completedAt)
        XCTAssertTrue(try XCTUnwrap(QuestEngine.status(assignment)).isComplete)
    }

    @MainActor
    func testDailyLedgerRebuildsExactTimeAndXP() throws {
        let container = try makeV4Container()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Cooking",
            symbolName: "fork.knife",
            accentHex: "FFFFFF",
            category: "Home"
        )
        context.insert(skill)
        let end = Date(timeIntervalSince1970: 2_000_000_000)
        context.insert(
            SkillSession(
                skillID: skill.id,
                startedAt: end.addingTimeInterval(-3),
                endedAt: end,
                activeSeconds: 3
            )
        )
        context.insert(
            SkillSession(
                skillID: skill.id,
                startedAt: end.addingTimeInterval(-63),
                endedAt: end.addingTimeInterval(60),
                activeSeconds: 60
            )
        )
        try context.save()

        try ActivityDayLedgerService.rebuildAll(in: context)
        let ledger = try XCTUnwrap(
            context.fetch(FetchDescriptor<ActivityDayLedger>()).first
        )
        XCTAssertEqual(ledger.totalActiveSeconds, 63)
        XCTAssertEqual(ledger.xpEarned, 21)
        XCTAssertEqual(ledger.sessionCount, 2)
        XCTAssertEqual(ledger.distinctSkillCount, 1)
    }

    @MainActor
    func testLongerSessionCreatesPersonalBestReveal() {
        let skill = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning"
        )
        let firstEnd = Date(timeIntervalSince1970: 100_000)
        let first = SkillSession(
            skillID: skill.id,
            startedAt: firstEnd.addingTimeInterval(-600),
            endedAt: firstEnd,
            activeSeconds: 600
        )
        let secondEnd = firstEnd.addingTimeInterval(86_400)
        let second = SkillSession(
            skillID: skill.id,
            startedAt: secondEnd.addingTimeInterval(-900),
            endedAt: secondEnd,
            activeSeconds: 900
        )

        let records = PersonalRecordEngine.newRecords(
            triggeringSession: second,
            beforeSessions: [first],
            afterSessions: [first, second],
            skills: [skill]
        )

        XCTAssertTrue(records.contains { $0.kind == .longestSkillSession })
        XCTAssertEqual(
            records.first { $0.kind == .longestSkillSession }?.previousValue,
            600
        )
    }

    @MainActor
    private func makeV4Container() throws -> ModelContainer {
        let schema = Schema([
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
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

final class CharacterProgressionV5Tests: XCTestCase {
    @MainActor
    func testEffectiveDatedAssignmentsPreserveEarlierPathHistory() {
        let skillID = UUID()
        let insight = SkillPathAssignment(
            id: "insight",
            skillID: skillID,
            pathRawValue: CharacterPath.insight.rawValue,
            effectiveFrom: Date(timeIntervalSince1970: 100),
            isConfirmed: true
        )
        let craft = SkillPathAssignment(
            id: "craft",
            skillID: skillID,
            pathRawValue: CharacterPath.craft.rawValue,
            effectiveFrom: Date(timeIntervalSince1970: 300),
            isConfirmed: true
        )
        let first = SkillSession(
            skillID: skillID,
            startedAt: Date(timeIntervalSince1970: 140),
            endedAt: Date(timeIntervalSince1970: 200),
            activeSeconds: 60
        )
        let second = SkillSession(
            skillID: skillID,
            startedAt: Date(timeIntervalSince1970: 340),
            endedAt: Date(timeIntervalSince1970: 400),
            activeSeconds: 60
        )

        let totals = CharacterProgressionEngine.totals(
            sessions: [first, second],
            assignments: [insight, craft]
        )

        XCTAssertEqual(totals[.insight], 60)
        XCTAssertEqual(totals[.craft], 60)
    }

    @MainActor
    func testPathTitleRemainsEarnedAfterHistoryCorrection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        context.insert(skill)
        CharacterProgressionService.recordInitialAssignment(
            skill: skill,
            path: .insight,
            in: context
        )
        let requiredSeconds = ProgressionEngine.cumulativeXP(
            toReach: 25,
            curveVersion: 1
        ) * ProgressionEngine.secondsPerXP(curveVersion: 1)
        let session = SkillSession(
            skillID: skill.id,
            startedAt: Date(timeIntervalSince1970: 200),
            endedAt: Date(timeIntervalSince1970: 200 + Double(requiredSeconds)),
            activeSeconds: requiredSeconds
        )
        context.insert(session)

        _ = try CharacterProgressionService.reconcile(
            skills: [skill],
            beforeSessions: [],
            afterSessions: [session],
            triggeringSession: session,
            in: context,
            now: session.endedAt
        )
        try context.save()
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<CharacterTitleUnlock>())
                .contains { $0.id == "path-title|insight|25" }
        )

        _ = try CharacterProgressionService.reconcile(
            skills: [skill],
            beforeSessions: [session],
            afterSessions: [],
            triggeringSession: nil,
            in: context,
            now: session.endedAt.addingTimeInterval(1)
        )
        try context.save()

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<CharacterTitleUnlock>())
                .contains { $0.id == "path-title|insight|25" }
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CharacterPathLedger>())
                .first { $0.pathRawValue == CharacterPath.insight.rawValue }?
                .totalActiveSeconds,
            0
        )
    }

    @MainActor
    func testWeeklyBoardReservesACharacterPathQuest() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let skill = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning",
            createdAt: now.addingTimeInterval(-86_400)
        )
        let assignment = SkillPathAssignment(
            id: "reading-path",
            skillID: skill.id,
            pathRawValue: CharacterPath.insight.rawValue,
            effectiveFrom: skill.createdAt,
            isConfirmed: true
        )
        let generated = QuestEngine.makeAssignments(
            cadence: .weekly,
            skills: [skill],
            sessions: [],
            existingAssignments: [],
            pathAssignments: [assignment],
            now: now
        )

        XCTAssertEqual(generated.count, 2)
        XCTAssertTrue(generated.contains { $0.templateID == "weekly-long-haul" })
        XCTAssertTrue(generated.contains { $0.templateID == "weekly-character-path" })
        XCTAssertEqual(
            generated.first { $0.templateID == "weekly-character-path" }?.targetPathRawValue,
            CharacterPath.insight.rawValue
        )
    }

    @MainActor
    func testExpertChallengeCompletionCreatesPermanentTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let skill = LifeSkill(
            name: "Cooking",
            symbolName: "frying.pan.fill",
            accentHex: "FFFFFF",
            category: "Home"
        )
        context.insert(skill)
        CharacterProgressionService.recordInitialAssignment(
            skill: skill,
            path: .craft,
            in: context
        )
        let requiredForExpert = ProgressionEngine.cumulativeXP(
            toReach: 75,
            curveVersion: 1
        ) * ProgressionEngine.secondsPerXP(curveVersion: 1)
        let historyEnd = Date(timeIntervalSince1970: 1_000_000)
        let history = SkillSession(
            skillID: skill.id,
            startedAt: historyEnd.addingTimeInterval(TimeInterval(-requiredForExpert)),
            endedAt: historyEnd,
            activeSeconds: requiredForExpert
        )
        context.insert(history)
        try context.save()

        let challengeStart = historyEnd.addingTimeInterval(1)
        let challenge = try CharacterProgressionService.startExpertChallenge(
            skill: skill,
            kind: .activeTime,
            in: context,
            now: challengeStart
        )
        let completingSession = SkillSession(
            skillID: skill.id,
            startedAt: challengeStart,
            endedAt: challengeStart.addingTimeInterval(10 * 3_600),
            activeSeconds: 10 * 3_600
        )
        context.insert(completingSession)

        let outcome = try CharacterProgressionService.reconcile(
            skills: [skill],
            beforeSessions: [history],
            afterSessions: [history, completingSession],
            triggeringSession: completingSession,
            in: context,
            now: completingSession.endedAt
        )
        try context.save()

        XCTAssertNotNil(challenge.completedAt)
        XCTAssertEqual(outcome.expertChallengesCompleted.map(\.id), [challenge.id])
        XCTAssertTrue(outcome.titlesUnlocked.contains { $0.title == "Expert of Cooking" })
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<CharacterTitleUnlock>())
                .contains { $0.id.hasPrefix("expert|") }
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SkillingTimeSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

final class SchemaMigrationV5Tests: XCTestCase {
    @MainActor
    func testV3StoreMigratesWithoutLosingAuthoritativeHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillingTimeMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("Store.sqlite")
        let skillID = UUID()
        let sessionID = UUID()
        let endedAt = Date(timeIntervalSince1970: 2_000_000_000)

        do {
            let oldSchema = Schema(versionedSchema: SkillingTimeSchemaV3.self)
            let oldConfiguration = ModelConfiguration(
                "migration-test",
                schema: oldSchema,
                url: storeURL
            )
            let oldContainer = try ModelContainer(
                for: oldSchema,
                configurations: [oldConfiguration]
            )
            let oldContext = ModelContext(oldContainer)
            oldContext.insert(
                SkillingTimeSchemaV3.LifeSkill(
                    id: skillID,
                    name: "Reading",
                    symbolName: "book",
                    accentHex: "FFFFFF",
                    category: "Learning"
                )
            )
            oldContext.insert(
                SkillingTimeSchemaV3.SkillSession(
                    id: sessionID,
                    skillID: skillID,
                    startedAt: endedAt.addingTimeInterval(-1_800),
                    endedAt: endedAt,
                    activeSeconds: 1_800,
                    note: "Preserve this"
                )
            )
            try oldContext.save()
        }

        let newSchema = Schema(versionedSchema: SkillingTimeSchemaV5.self)
        let newConfiguration = ModelConfiguration(
            "migration-test",
            schema: newSchema,
            url: storeURL
        )
        let newContainer = try ModelContainer(
            for: newSchema,
            migrationPlan: SkillingTimeMigrationPlan.self,
            configurations: [newConfiguration]
        )
        let newContext = ModelContext(newContainer)
        let skill = try XCTUnwrap(
            newContext.fetch(FetchDescriptor<LifeSkill>()).first { $0.id == skillID }
        )
        let session = try XCTUnwrap(
            newContext.fetch(FetchDescriptor<SkillSession>()).first { $0.id == sessionID }
        )

        XCTAssertEqual(skill.name, "Reading")
        XCTAssertEqual(session.skillID, skillID)
        XCTAssertEqual(session.activeSeconds, 1_800)
        XCTAssertEqual(session.note, "Preserve this")
        XCTAssertNil(session.recordedFocusGoal)
    }

    @MainActor
    func testV4StoreMigratesAndCharacterHistoryRebuilds() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillingTimeV5Migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("Store.sqlite")
        let skillID = UUID()
        let sessionID = UUID()
        let endedAt = Date(timeIntervalSince1970: 2_000_000_000)

        do {
            let oldSchema = Schema(versionedSchema: SkillingTimeSchemaV4.self)
            let oldConfiguration = ModelConfiguration(
                "migration-test",
                schema: oldSchema,
                url: storeURL
            )
            let oldContainer = try ModelContainer(
                for: oldSchema,
                configurations: [oldConfiguration]
            )
            let oldContext = ModelContext(oldContainer)
            oldContext.insert(
                SkillingTimeSchemaV4.LifeSkill(
                    id: skillID,
                    name: "Reading",
                    symbolName: "book",
                    accentHex: "FFFFFF",
                    category: "Learning"
                )
            )
            oldContext.insert(
                SkillingTimeSchemaV4.SkillSession(
                    id: sessionID,
                    skillID: skillID,
                    startedAt: endedAt.addingTimeInterval(-1_800),
                    endedAt: endedAt,
                    activeSeconds: 1_800,
                    note: "Preserve v4 history"
                )
            )
            try oldContext.save()
        }

        let newSchema = Schema(versionedSchema: SkillingTimeSchemaV5.self)
        let newConfiguration = ModelConfiguration(
            "migration-test",
            schema: newSchema,
            url: storeURL
        )
        let newContainer = try ModelContainer(
            for: newSchema,
            migrationPlan: SkillingTimeMigrationPlan.self,
            configurations: [newConfiguration]
        )
        let context = ModelContext(newContainer)

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SkillSession>()).first?.note,
            "Preserve v4 history"
        )
        try CharacterProgressionService.prepare(in: context, now: endedAt)

        let assignment = try XCTUnwrap(
            context.fetch(FetchDescriptor<SkillPathAssignment>()).first
        )
        let ledger = try XCTUnwrap(
            context.fetch(FetchDescriptor<CharacterPathLedger>()).first {
                $0.pathRawValue == CharacterPath.insight.rawValue
            }
        )
        XCTAssertEqual(assignment.skillID, skillID)
        XCTAssertEqual(assignment.path, .insight)
        XCTAssertEqual(ledger.totalActiveSeconds, 1_800)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<CharacterProfile>()).first)
    }
}

final class ProgressionNotificationPlannerTests: XCTestCase {
    func testRunningSessionSchedulesExactNextLevelBoundary() {
        let skill = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning"
        )
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = ActiveSessionSnapshot(
            id: UUID(),
            skillID: skill.id,
            startedAt: now.addingTimeInterval(-45),
            accumulatedActiveSeconds: 0,
            activeSegmentStartedAt: now.addingTimeInterval(-45),
            finishRequestedAt: nil,
            shouldResumeAfterCancelledFinish: nil,
            focusGoal: nil
        )

        let plan = ProgressionNotificationPlanner.plan(
            snapshot: snapshot,
            skill: skill,
            baseTotalSeconds: 0,
            at: now
        )

        XCTAssertEqual(plan?.targetTotalXP, 115)
        XCTAssertEqual(plan?.fireAfterSeconds, 300)
        XCTAssertTrue(plan?.body.contains("Level 2") == true)
    }

    func testPausedOrPendingSessionDoesNotSchedule() {
        let skill = LifeSkill(
            name: "Reading",
            symbolName: "book",
            accentHex: "FFFFFF",
            category: "Learning"
        )
        let paused = ActiveSessionSnapshot(
            id: UUID(),
            skillID: skill.id,
            startedAt: .now,
            accumulatedActiveSeconds: 45,
            activeSegmentStartedAt: nil,
            finishRequestedAt: nil,
            shouldResumeAfterCancelledFinish: nil,
            focusGoal: nil
        )
        var pending = paused
        pending.finishRequestedAt = .now

        XCTAssertNil(
            ProgressionNotificationPlanner.plan(
                snapshot: paused,
                skill: skill,
                baseTotalSeconds: 0
            )
        )
        XCTAssertNil(
            ProgressionNotificationPlanner.plan(
                snapshot: pending,
                skill: skill,
                baseTotalSeconds: 0
            )
        )
    }
}
