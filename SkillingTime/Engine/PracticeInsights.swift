import Foundation
import SwiftData
import UserNotifications
import WidgetKit

// MARK: - One More Level?

struct OneMoreLevelOffer: Equatable, Sendable {
    let secondsRemaining: Int
    let targetLabel: String

    var promptText: String {
        let minutes = max(1, Int((Double(secondsRemaining) / 60).rounded(.up)))
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes") to \(targetLabel)."
    }
}

enum OneMoreLevel {
    /// Offer to keep going only when the next level is genuinely close.
    static let windowSeconds = 10 * 60

    static func offer(
        totalSeconds: Int,
        curveVersion: Int,
        windowSeconds: Int = OneMoreLevel.windowSeconds
    ) -> OneMoreLevelOffer? {
        let secondsPerXP = ProgressionEngine.secondsPerXP(curveVersion: curveVersion)
        let totalXP = ProgressionEngine.xp(forActiveSeconds: totalSeconds, curveVersion: curveVersion)
        let progress = ProgressionEngine.progress(forTotalXP: totalXP, curveVersion: curveVersion)
        let targetXP = ProgressionEngine.nextThresholdXP(after: progress, curveVersion: curveVersion)
        // Seconds already banked toward the next XP point count too.
        let remaining = max(0, targetXP * secondsPerXP - max(0, totalSeconds))
        guard remaining > 0, remaining <= windowSeconds else { return nil }

        let label = progress.level < ProgressionEngine.maximumLevel(curveVersion: curveVersion)
            ? "Level \(progress.level + 1)"
            : "Mastery star \(progress.masteryStars + 1)"
        return OneMoreLevelOffer(secondsRemaining: remaining, targetLabel: label)
    }
}

// MARK: - Pace and projections

struct WeeklyPracticeBucket: Identifiable, Equatable, Sendable {
    let weekStart: Date
    let seconds: Int
    var id: Date { weekStart }
}

struct PracticeMilestoneEstimate: Equatable, Sendable {
    let title: String
    let secondsNeeded: Int
    let estimatedDate: Date?
}

struct SkillPaceSummary: Equatable, Sendable {
    let windowDays: Int
    let secondsInWindow: Int
    let weeks: [WeeklyPracticeBucket]
    let nextLevel: PracticeMilestoneEstimate?
    let nextRank: PracticeMilestoneEstimate?

    var averageSecondsPerDay: Double {
        Double(secondsInWindow) / Double(max(1, windowDays))
    }

    var averageSecondsPerWeek: Int {
        Int((averageSecondsPerDay * 7).rounded())
    }
}

enum SkillPace {
    static let windowDays = 28
    static let weekCount = 8

    /// Pace is measured over the last `windowDays` of real sessions; projections
    /// simply extend that pace. Nothing is estimated without recent practice.
    static func summary(
        sessions: [SkillSession],
        curveVersion: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SkillPaceSummary {
        let todayStart = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: todayStart) ?? todayStart
        let recentSeconds = sessions
            .filter { $0.creditedAt >= windowStart && $0.creditedAt <= now }
            .reduce(0) { $0 + max(0, $1.activeSeconds) }

        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        var weeks: [WeeklyPracticeBucket] = []
        for offset in stride(from: weekCount - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            let seconds = sessions
                .filter { $0.creditedAt >= start && $0.creditedAt < end }
                .reduce(0) { $0 + max(0, $1.activeSeconds) }
            weeks.append(WeeklyPracticeBucket(weekStart: start, seconds: seconds))
        }

        let totalSeconds = sessions.reduce(0) { $0 + max(0, $1.activeSeconds) }
        let secondsPerXP = ProgressionEngine.secondsPerXP(curveVersion: curveVersion)
        let totalXP = ProgressionEngine.xp(forActiveSeconds: totalSeconds, curveVersion: curveVersion)
        let progress = ProgressionEngine.progress(forTotalXP: totalXP, curveVersion: curveVersion)
        let perDay = Double(recentSeconds) / Double(windowDays)

        func estimate(title: String, targetXP: Int) -> PracticeMilestoneEstimate? {
            let needed = max(0, targetXP * secondsPerXP - totalSeconds)
            guard needed > 0 else { return nil }
            let date = perDay > 0
                ? now.addingTimeInterval((Double(needed) / perDay) * 86_400)
                : nil
            return PracticeMilestoneEstimate(title: title, secondsNeeded: needed, estimatedDate: date)
        }

        let maximumLevel = ProgressionEngine.maximumLevel(curveVersion: curveVersion)
        let nextLevel = estimate(
            title: progress.level < maximumLevel
                ? "Level \(progress.level + 1)"
                : "Mastery star \(progress.masteryStars + 1)",
            targetXP: ProgressionEngine.nextThresholdXP(after: progress, curveVersion: curveVersion)
        )
        let nextRank = [25, 50, 75, 100]
            .first { $0 > progress.level }
            .flatMap { milestone in
                estimate(
                    title: "\(ProgressionEngine.rank(for: milestone).rawValue) (Level \(milestone))",
                    targetXP: ProgressionEngine.cumulativeXP(toReach: milestone, curveVersion: curveVersion)
                )
            }

        return SkillPaceSummary(
            windowDays: windowDays,
            secondsInWindow: recentSeconds,
            weeks: weeks,
            nextLevel: nextLevel,
            nextRank: nextRank
        )
    }
}

// MARK: - Widget snapshot

@MainActor
enum WidgetSnapshotPublisher {
    /// Writes the App Group snapshot the widgets, control, and Siri read, and
    /// reloads them only when something they show actually changed.
    static func publish(in modelContext: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        guard let skills = try? modelContext.fetch(
            FetchDescriptor<LifeSkill>(sortBy: [SortDescriptor(\.sortOrder)])
        ),
            let ledgers = try? modelContext.fetch(FetchDescriptor<SkillLedger>()),
            let days = try? modelContext.fetch(FetchDescriptor<ActivityDayLedger>())
        else { return }

        let snapshot = make(skills: skills, ledgers: ledgers, days: days, now: now, calendar: calendar)
        guard WidgetSnapshotStore.save(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
        SkillingTimeShortcuts.updateAppShortcutParameters()
    }

    nonisolated static func make(
        skills: [LifeSkill],
        ledgers: [SkillLedger],
        days: [ActivityDayLedger],
        now: Date,
        calendar: Calendar
    ) -> WidgetSnapshot {
        let ledgerBySkill = Dictionary(ledgers.map { ($0.skillID, $0) }, uniquingKeysWith: { first, _ in first })
        let summaries = skills.filter { !$0.isArchived }.map { skill -> WidgetSkillSummary in
            let ledger = ledgerBySkill[skill.id]
            let totalSeconds = ledger?.totalActiveSeconds ?? 0
            let xp = ProgressionEngine.xp(forActiveSeconds: totalSeconds, curveVersion: skill.progressionCurveVersion)
            let progress = ProgressionEngine.progress(forTotalXP: xp, curveVersion: skill.progressionCurveVersion)
            let target = ProgressionEngine.nextThresholdXP(after: progress, curveVersion: skill.progressionCurveVersion)
            let remaining = target * ProgressionEngine.secondsPerXP(curveVersion: skill.progressionCurveVersion)
                - totalSeconds
            return WidgetSkillSummary(
                id: skill.id,
                name: skill.name,
                symbolName: skill.symbolName,
                accentHex: skill.accentHex,
                level: progress.level,
                fractionToNextLevel: progress.fractionComplete,
                secondsToNextLevel: remaining > 0 ? remaining : nil,
                latestSessionAt: ledger?.latestSessionAt
            )
        }

        let todayStart = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> ActivityDayLedger? {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            return days.first { calendar.isDate($0.dayStart, inSameDayAs: date) }
        }
        let today = day(0)
        let week = (0..<7).reversed().map { day($0)?.totalActiveSeconds ?? 0 }

        return WidgetSnapshot(
            generatedAt: now,
            skills: summaries,
            dayStart: todayStart,
            todaySeconds: today?.totalActiveSeconds ?? 0,
            todayXP: today?.xpEarned ?? 0,
            weekDaySeconds: week
        )
    }
}

// MARK: - Practice reminders

enum PracticeReminderInterval: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case threeDays = 3
    case week = 7
    case twoWeeks = 14

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .threeDays: "After 3 days"
        case .week: "After a week"
        case .twoWeeks: "After two weeks"
        }
    }
}

enum PracticeReminderPlanner {
    static let reminderHour = 18

    /// First reminder `intervalDays` after the last practice (or creation), at
    /// `reminderHour`. If that moment has passed it repeats on the same cadence,
    /// so an unpracticed Skill is mentioned at most once per interval, never daily.
    static func nextFireDate(
        lastPracticedAt: Date?,
        createdAt: Date,
        intervalDays: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard intervalDays > 0 else { return nil }
        let anchor = calendar.startOfDay(for: lastPracticedAt ?? createdAt)
        var steps = 1
        while steps < 1_000 {
            guard let day = calendar.date(byAdding: .day, value: intervalDays * steps, to: anchor),
                  let fire = calendar.date(
                      bySettingHour: reminderHour,
                      minute: 0,
                      second: 0,
                      of: day
                  ) else { return nil }
            if fire > now { return fire }
            steps += 1
        }
        return nil
    }
}

@MainActor
enum PracticeReminderScheduler {
    static let identifierPrefix = "skillingtime.practice-reminder."
    private static let settingsKey = "skillingtime.practice-reminders.v1"

    static func interval(
        for skillID: UUID,
        defaults: UserDefaults = .standard
    ) -> PracticeReminderInterval {
        let stored = (defaults.dictionary(forKey: settingsKey) as? [String: Int])?[skillID.uuidString] ?? 0
        return PracticeReminderInterval(rawValue: stored) ?? .off
    }

    static func setInterval(
        _ interval: PracticeReminderInterval,
        for skillID: UUID,
        defaults: UserDefaults = .standard
    ) {
        var settings = (defaults.dictionary(forKey: settingsKey) as? [String: Int]) ?? [:]
        settings[skillID.uuidString] = interval == .off ? nil : interval.rawValue
        defaults.set(settings, forKey: settingsKey)
    }

    /// Asks for notification permission when a reminder is first turned on.
    static func requestAuthorizationIfNeeded(
        center: UNUserNotificationCenter = .current()
    ) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    /// Replaces every pending practice reminder with one per enabled, active Skill.
    static func reschedule(
        in modelContext: ModelContext,
        center: UNUserNotificationCenter = .current(),
        now: Date = .now
    ) async {
        guard let skills = try? modelContext.fetch(FetchDescriptor<LifeSkill>()),
              let ledgers = try? modelContext.fetch(FetchDescriptor<SkillLedger>()) else { return }
        let latestBySkill = Dictionary(
            ledgers.map { ($0.skillID, $0.latestSessionAt) },
            uniquingKeysWith: { first, _ in first }
        )
        let plans = skills.compactMap { skill -> (LifeSkill, Date)? in
            guard !skill.isArchived else { return nil }
            let days = interval(for: skill.id).rawValue
            guard let fire = PracticeReminderPlanner.nextFireDate(
                lastPracticedAt: latestBySkill[skill.id] ?? nil,
                createdAt: skill.createdAt,
                intervalDays: days,
                now: now
            ) else { return nil }
            return (skill, fire)
        }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        )

        let settings = await center.notificationSettings()
        let allowed: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
        guard allowed.contains(settings.authorizationStatus) else { return }

        for (skill, fire) in plans {
            let content = UNMutableNotificationContent()
            content.title = "Time for some \(skill.name)?"
            content.body = "Whenever you're ready. Even a few minutes counts."
            content.sound = .default
            content.userInfo = ["skillID": skill.id.uuidString]
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fire
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + skill.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}

// MARK: - Launch work

enum RewardBackfillGate {
    private static let key = "skillingtime.reward-backfill.fingerprint"

    /// Reward history is a pure function of Skills, sessions, and the app's reward
    /// definitions, and every commit, edit, and deletion already reconciles it.
    /// The launch backfill is a safety net, so it runs only when that input changed.
    static func fingerprint(
        skills: [LifeSkill],
        sessions: [SkillSession],
        appBuild: String
    ) -> String {
        let seconds = sessions.reduce(0) { $0 + $1.activeSeconds }
        let ends = sessions.reduce(0.0) { $0 + $1.endedAt.timeIntervalSince1970 }
        let curves = skills.reduce(0) { $0 + $1.progressionCurveVersion }
        return "\(appBuild)|\(skills.count)|\(curves)|\(sessions.count)|\(seconds)|\(Int64(ends))"
    }

    static func isCurrent(_ fingerprint: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: key) == fingerprint
    }

    static func record(_ fingerprint: String, defaults: UserDefaults = .standard) {
        defaults.set(fingerprint, forKey: key)
    }
}
