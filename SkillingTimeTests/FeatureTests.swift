import SwiftData
import XCTest
@testable import SkillingTime

final class BackupServiceTests: XCTestCase {
    @MainActor
    func testRoundTripRestoresHistoryReplacesEmptyStarterAndIsIdempotent() throws {
        let source = ModelContext(try makeInMemoryContainer())
        let skill = LifeSkill(name: "Reading", symbolName: "book", accentHex: "5D83C4", category: "Learning")
        source.insert(skill)
        try source.save()

        let firstEnd = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, seconds) in [1_800, 2_400].enumerated() {
            let end = firstEnd.addingTimeInterval(Double(index) * 86_400)
            _ = try SessionCommitService.commit(
                draft: CompletedSessionDraft(
                    id: UUID(),
                    skillID: skill.id,
                    startedAt: end.addingTimeInterval(-Double(seconds)),
                    endedAt: end,
                    activeSeconds: seconds,
                    focusGoal: nil,
                    shouldResumeOnCancel: false
                ),
                countedSeconds: seconds,
                note: "Session \(index)",
                source: .timer,
                skill: skill,
                in: source,
                now: end
            )
        }

        let backup = try BackupService.decode(
            try BackupService.encode(try BackupService.makeBackup(in: source))
        )
        XCTAssertEqual(backup.sessions.count, 2)
        XCTAssertFalse(backup.achievements.isEmpty)

        // A fresh install: an untouched starter with the same name exists.
        let target = ModelContext(try makeInMemoryContainer())
        let starter = LifeSkill(name: "reading", symbolName: "book", accentHex: "FFFFFF", category: "Learning")
        target.insert(starter)
        try target.save()

        let first = try BackupService.restore(backup, into: target)
        XCTAssertEqual(first.sessionsAdded, 2)
        XCTAssertEqual(first.skillsAdded, 1)
        XCTAssertEqual(first.skillsReplaced, 1)

        let skills = try target.fetch(FetchDescriptor<LifeSkill>())
        XCTAssertEqual(skills.map(\.id), [skill.id])
        let sessions = try target.fetch(FetchDescriptor<SkillSession>())
        XCTAssertEqual(Set(sessions.map(\.note)), ["Session 0", "Session 1"])
        let ledger = try XCTUnwrap(target.fetch(FetchDescriptor<SkillLedger>()).first)
        XCTAssertEqual(ledger.totalActiveSeconds, 4_200)
        XCTAssertEqual(
            try target.fetch(FetchDescriptor<AchievementUnlock>()).count,
            try source.fetch(FetchDescriptor<AchievementUnlock>()).count
        )

        let second = try BackupService.restore(backup, into: target)
        XCTAssertEqual(second.sessionsAdded, 0)
        XCTAssertEqual(second.skillsAdded, 0)
        XCTAssertEqual(second.otherRecordsAdded, 0)
        XCTAssertEqual(try target.fetch(FetchDescriptor<SkillSession>()).count, 2)
    }

    @MainActor
    func testNewerBackupFormatIsRejectedWithoutChanges() throws {
        let data = Data(#"{"formatVersion": 99}"#.utf8)
        XCTAssertThrowsError(try BackupService.decode(data)) { error in
            guard case BackupError.unsupportedFormat(99) = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertThrowsError(try BackupService.decode(Data("not json".utf8)))
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SkillingTimeSchemaV5.self)
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}

final class PracticeInsightsTests: XCTestCase {
    func testOneMoreLevelOffersOnlyWithinTheWindow() {
        // Level 3 needs 250 XP (750 s). At 450 s, 300 s remain.
        let offer = OneMoreLevel.offer(totalSeconds: 450, curveVersion: 1)
        XCTAssertEqual(offer?.secondsRemaining, 300)
        XCTAssertEqual(offer?.targetLabel, "Level 3")
        XCTAssertEqual(offer?.promptText, "5 minutes to Level 3.")
        XCTAssertNil(OneMoreLevel.offer(totalSeconds: 450, curveVersion: 1, windowSeconds: 200))
    }

    func testPaceProjectsFromRecentPracticeOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let skillID = UUID()
        let recent = (1...4).map { day in
            SkillSession(
                skillID: skillID,
                startedAt: now.addingTimeInterval(-Double(day) * 86_400 - 3_600),
                endedAt: now.addingTimeInterval(-Double(day) * 86_400),
                activeSeconds: 3_600
            )
        }

        let summary = SkillPace.summary(sessions: recent, curveVersion: 1, now: now, calendar: calendar)
        XCTAssertEqual(summary.secondsInWindow, 14_400)
        XCTAssertEqual(summary.weeks.count, 8)
        XCTAssertEqual(summary.weeks.reduce(0) { $0 + $1.seconds }, 14_400)
        let estimate = try? XCTUnwrap(summary.nextLevel?.estimatedDate)
        XCTAssertNotNil(estimate)
        XCTAssertGreaterThan(estimate ?? now, now)

        let old = SkillSession(
            skillID: skillID,
            startedAt: now.addingTimeInterval(-90 * 86_400 - 3_600),
            endedAt: now.addingTimeInterval(-90 * 86_400),
            activeSeconds: 3_600
        )
        let stale = SkillPace.summary(sessions: [old], curveVersion: 1, now: now, calendar: calendar)
        XCTAssertEqual(stale.secondsInWindow, 0)
        XCTAssertNil(stale.nextLevel?.estimatedDate, "No recent practice means no projection.")
    }

    func testReminderRepeatsOnItsIntervalNeverDaily() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let practiced = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 10))
        )
        let expectedFirst = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 18))
        )
        let expectedSecond = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 18))
        )

        XCTAssertEqual(
            PracticeReminderPlanner.nextFireDate(
                lastPracticedAt: practiced,
                createdAt: practiced,
                intervalDays: 7,
                now: practiced.addingTimeInterval(3 * 86_400),
                calendar: calendar
            ),
            expectedFirst
        )
        XCTAssertEqual(
            PracticeReminderPlanner.nextFireDate(
                lastPracticedAt: practiced,
                createdAt: practiced,
                intervalDays: 7,
                now: expectedFirst.addingTimeInterval(3_600),
                calendar: calendar
            ),
            expectedSecond
        )
        XCTAssertNil(
            PracticeReminderPlanner.nextFireDate(
                lastPracticedAt: practiced,
                createdAt: practiced,
                intervalDays: 0,
                now: practiced,
                calendar: calendar
            )
        )
    }

    func testWidgetSnapshotRules() throws {
        let practiced = WidgetSkillSummary(
            id: UUID(), name: "Cooking", symbolName: "frying.pan.fill", accentHex: "D97A43",
            level: 4, fractionToNextLevel: 0.5, secondsToNextLevel: 900, latestSessionAt: .now
        )
        let untouched = WidgetSkillSummary(
            id: UUID(), name: "Reading", symbolName: "book", accentHex: "5D83C4",
            level: 1, fractionToNextLevel: 0, secondsToNextLevel: 60, latestSessionAt: nil
        )
        let dayStart = Calendar.current.startOfDay(for: .now)
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            skills: [untouched, practiced],
            dayStart: dayStart,
            todaySeconds: 1_200,
            todayXP: 400,
            weekDaySeconds: [0, 0, 0, 0, 0, 0, 1_200]
        )
        XCTAssertEqual(snapshot.closestToLevel?.id, practiced.id, "Never-practiced Skills are not nudged.")
        XCTAssertEqual(snapshot.recentSkills.map(\.id), [practiced.id, untouched.id])
        XCTAssertEqual(snapshot.todaySeconds(at: dayStart.addingTimeInterval(3_600)), 1_200)
        XCTAssertEqual(snapshot.todaySeconds(at: dayStart.addingTimeInterval(90_000)), 0)

        let suiteName = "FeatureTests.pending-start"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let requestedAt = Date(timeIntervalSince1970: 1_700_000_000)

        WidgetSnapshotStore.requestStart(skillID: practiced.id, at: requestedAt, defaults: defaults)
        XCTAssertEqual(
            WidgetSnapshotStore.takePendingStart(at: requestedAt.addingTimeInterval(30), defaults: defaults),
            practiced.id
        )
        XCTAssertNil(WidgetSnapshotStore.takePendingStart(defaults: defaults), "A request is used once.")

        WidgetSnapshotStore.requestStart(skillID: practiced.id, at: requestedAt, defaults: defaults)
        XCTAssertNil(
            WidgetSnapshotStore.takePendingStart(at: requestedAt.addingTimeInterval(3_600), defaults: defaults),
            "A stale tap never starts a timer later."
        )
    }
}

final class SkillbookLayoutTests: XCTestCase {
    func testColumnPreferenceIsClampedAndLargeTextUsesTwo() {
        XCTAssertEqual(SkillbookLayout.columnCount(preferred: 3, isAccessibilitySize: false), 3)
        XCTAssertEqual(SkillbookLayout.columnCount(preferred: 4, isAccessibilitySize: false), 4)
        XCTAssertEqual(SkillbookLayout.columnCount(preferred: 9, isAccessibilitySize: false), 4)
        XCTAssertEqual(SkillbookLayout.columnCount(preferred: 0, isAccessibilitySize: false), 2)
        XCTAssertEqual(SkillbookLayout.columnCount(preferred: 4, isAccessibilitySize: true), 2)
        XCTAssertEqual(SkillCardDensity(columnCount: 2), .regular)
        XCTAssertEqual(SkillCardDensity(columnCount: 3), .compact)
        XCTAssertEqual(SkillCardDensity(columnCount: 4), .dense)
    }
}

final class SimplifiedExperienceTests: XCTestCase {
    func testSummaryShowsOnlyVisibleSystems() {
        let start = ProgressionEngine.progress(forTotalXP: 0, curveVersion: 1)
        let end = ProgressionEngine.progress(forTotalXP: 500, curveVersion: 1)
        let outcome = SessionOutcome(
            id: UUID(),
            skillID: UUID(),
            skillName: "Cooking",
            symbolName: "frying.pan.fill",
            accentHex: "D97A43",
            durationSeconds: 1_500,
            xpEarned: 500,
            startingProgress: start,
            endingProgress: end,
            levelsCrossed: [2, 3, 4],
            chroniclesUnlocked: [],
            achievementsUnlocked: Array(AchievementEngine.skillDefinitions.prefix(2)),
            questsCompleted: [],
            personalRecords: [],
            pathProgress: nil,
            characterTitlesUnlocked: [],
            expertChallengesCompleted: [],
            capabilitiesUnlocked: [.focusGoals, .legacy],
            focusGoalResult: nil,
            note: "Soup",
            wasAlreadyCommitted: false
        )

        let visible = AppFeatures.visibleOutcome(outcome)

        XCTAssertEqual(visible.levelsCrossed, [2, 3, 4], "The core loop is always shown.")
        XCTAssertEqual(visible.xpEarned, 500)
        XCTAssertEqual(visible.note, "Soup")
        XCTAssertEqual(visible.achievementsUnlocked.isEmpty, !AppFeatures.achievementsGallery)
        XCTAssertEqual(
            visible.capabilitiesUnlocked,
            [SkillCapability.focusGoals, .legacy].filter(AppFeatures.isVisible)
        )
    }
}
