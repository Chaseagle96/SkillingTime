import Foundation

enum AchievementScope: Sendable {
    case skill
    case global
}

enum AchievementCriterion: Sendable {
    case skillLevel(Int)
    case skillDuration(Int)
    case skillSessionCount(Int)
    case longestSession(Int)
    case activeDays(Int)
    case returnAfterDays(Int)
    case activeWeeks(Int)
    case activeMonths(Int)
    case totalLevel(Int)
    case activeSkillCount(Int)
    case globalDuration(Int)
}

struct AchievementDefinition: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let systemImage: String
    let scope: AchievementScope
    let criterion: AchievementCriterion
}

struct AchievementStatus: Identifiable, Sendable {
    let definition: AchievementDefinition
    let skillID: UUID?
    let currentValue: Double
    let targetValue: Double
    let progressLabel: String

    var id: String {
        if let skillID {
            return "\(definition.id)-\(skillID.uuidString)"
        }
        return definition.id
    }

    var isUnlocked: Bool { currentValue >= targetValue }
    var fractionComplete: Double {
        guard targetValue > 0 else { return 1 }
        return min(max(currentValue / targetValue, 0), 1)
    }
}

enum AchievementEngine {
    static let skillDefinitions: [AchievementDefinition] = {
        var definitions: [AchievementDefinition] = []

        let levels: [(Int, String)] = [
            (5, "First Footing"), (10, "Finding a Rhythm"), (20, "Taking Shape"),
            (25, "Apprentice"), (40, "Practiced Hands"), (50, "Journeyman"),
            (60, "The Craft Deepens"), (75, "Expert"), (90, "Near the Summit"),
            (100, "Master")
        ]
        definitions += levels.map { level, title in
            AchievementDefinition(
                id: "skill-level-\(level)",
                title: title,
                description: "Reach Level \(level) in this Skill.",
                systemImage: level >= 75 ? "crown.fill" : "chevron.up.2",
                scope: .skill,
                criterion: .skillLevel(level)
            )
        }

        let durations: [(Int, String, String)] = [
            (10 * 60, "Ten Intentional Minutes", "Practice for 10 total minutes."),
            (30 * 60, "Half an Hour", "Practice for 30 total minutes."),
            (60 * 60, "The First Hour", "Practice for one total hour."),
            (5 * 3600, "Five Hours", "Practice for five total hours."),
            (10 * 3600, "Ten Hours", "Practice for ten total hours."),
            (25 * 3600, "A Day of Practice", "Practice for 25 total hours."),
            (50 * 3600, "Fifty Hours", "Practice for 50 total hours."),
            (100 * 3600, "A Hundred Hours", "Practice for 100 total hours."),
            (250 * 3600, "A Season of Work", "Practice for 250 total hours."),
            (500 * 3600, "Enduring Craft", "Practice for 500 total hours."),
            (1000 * 3600, "A Thousand Hours", "Practice for 1,000 total hours.")
        ]
        definitions += durations.map { seconds, title, description in
            AchievementDefinition(
                id: "skill-duration-\(seconds)",
                title: title,
                description: description,
                systemImage: "hourglass",
                scope: .skill,
                criterion: .skillDuration(seconds)
            )
        }

        let sessionCounts: [(Int, String)] = [
            (1, "The Beginning"), (5, "Returning"), (10, "Ten Sessions"),
            (25, "Steady Practice"), (50, "Fifty Returns"), (100, "Centurion"),
            (250, "The Long Practice"), (500, "Unwavering"), (1000, "A Living Ritual")
        ]
        definitions += sessionCounts.map { count, title in
            AchievementDefinition(
                id: "skill-sessions-\(count)",
                title: title,
                description: "Complete \(count.formatted()) \(count == 1 ? "session" : "sessions") in this Skill.",
                systemImage: "checkmark.seal.fill",
                scope: .skill,
                criterion: .skillSessionCount(count)
            )
        }

        let endurance: [(Int, String)] = [
            (15 * 60, "Settling In"), (30 * 60, "Focused Half Hour"),
            (60 * 60, "Deep Work"), (2 * 3600, "Long Form"), (4 * 3600, "Marathon")
        ]
        definitions += endurance.map { seconds, title in
            AchievementDefinition(
                id: "skill-endurance-\(seconds)",
                title: title,
                description: "Complete one session lasting \(DurationText.compact(seconds)).",
                systemImage: "timer",
                scope: .skill,
                criterion: .longestSession(seconds)
            )
        }

        let activeDays: [(Int, String)] = [
            (3, "Three Different Days"), (7, "A Week of Returns"),
            (14, "A Fortnight Remembered"), (30, "Thirty Active Days"),
            (60, "Seasoned"), (100, "One Hundred Days"),
            (250, "A Familiar Companion"), (365, "A Year in Days")
        ]
        definitions += activeDays.map { count, title in
            AchievementDefinition(
                id: "skill-active-days-\(count)",
                title: title,
                description: "Practice this Skill on \(count) different days.",
                systemImage: "calendar.badge.checkmark",
                scope: .skill,
                criterion: .activeDays(count)
            )
        }

        definitions += [
            AchievementDefinition(
                id: "skill-return-30",
                title: "The Return",
                description: "Return to this Skill after at least 30 days away.",
                systemImage: "arrow.uturn.backward.circle.fill",
                scope: .skill,
                criterion: .returnAfterDays(30)
            ),
            AchievementDefinition(
                id: "skill-weeks-4",
                title: "Four Chapters",
                description: "Practice during four different calendar weeks.",
                systemImage: "calendar",
                scope: .skill,
                criterion: .activeWeeks(4)
            ),
            AchievementDefinition(
                id: "skill-months-12",
                title: "Through the Year",
                description: "Practice during 12 different calendar months.",
                systemImage: "calendar.circle.fill",
                scope: .skill,
                criterion: .activeMonths(12)
            )
        ]

        return definitions
    }()

    static let globalDefinitions: [AchievementDefinition] = {
        var definitions: [AchievementDefinition] = []

        let totalLevels: [(Int, String)] = [
            (25, "A Growing Skillbook"), (50, "Many Paths"), (100, "Total Level 100"),
            (250, "A Life in Practice"), (500, "Keeper of the Skillbook"), (1000, "A Thousand Levels")
        ]
        definitions += totalLevels.map { level, title in
            AchievementDefinition(
                id: "global-level-\(level)",
                title: title,
                description: "Reach Total Level \(level).",
                systemImage: "books.vertical.fill",
                scope: .global,
                criterion: .totalLevel(level)
            )
        }

        let activeSkills: [(Int, String)] = [
            (1, "First Skill Awakened"), (3, "Well Rounded"),
            (5, "Many Talents"), (10, "Renaissance Life")
        ]
        definitions += activeSkills.map { count, title in
            AchievementDefinition(
                id: "global-skills-\(count)",
                title: title,
                description: "Record time in \(count) different Skills.",
                systemImage: "square.grid.2x2.fill",
                scope: .global,
                criterion: .activeSkillCount(count)
            )
        }

        let globalDurations: [(Int, String)] = [
            (3600, "An Hour Invested"), (10 * 3600, "Ten Hours Lived"),
            (100 * 3600, "The Hundred-Hour Chronicle"),
            (500 * 3600, "Five Hundred Hours"), (1000 * 3600, "A Thousand Hours of Becoming")
        ]
        definitions += globalDurations.map { seconds, title in
            AchievementDefinition(
                id: "global-duration-\(seconds)",
                title: title,
                description: "Record \(DurationText.compact(seconds)) across your Skillbook.",
                systemImage: "clock.badge.checkmark.fill",
                scope: .global,
                criterion: .globalDuration(seconds)
            )
        }

        return definitions
    }()

    static var achievementTypeCount: Int {
        skillDefinitions.count + globalDefinitions.count
    }

    static func statuses(for skill: LifeSkill, sessions: [SkillSession], calendar: Calendar = .current) -> [AchievementStatus] {
        let matching = SessionAnalytics.sessions(for: skill.id, in: sessions)
        let statistics = SessionAnalytics.statistics(for: skill.id, sessions: sessions, calendar: calendar)
        let xp = ProgressionEngine.xp(
            forActiveSeconds: statistics.totalSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        let level = ProgressionEngine.level(
            forTotalXP: xp,
            curveVersion: skill.progressionCurveVersion
        )
        let weeks = distinctWeekCount(in: matching, calendar: calendar)
        let months = distinctMonthCount(in: matching, calendar: calendar)
        let didReturn = containsReturnGap(in: matching, minimumDays: 30, calendar: calendar)

        return skillDefinitions.map { definition in
            let current: Double
            let target: Double
            let label: String

            switch definition.criterion {
            case .skillLevel(let value):
                current = Double(level)
                target = Double(value)
                label = "Level \(min(level, value)) of \(value)"
            case .skillDuration(let seconds):
                current = Double(statistics.totalSeconds)
                target = Double(seconds)
                label = "\(DurationText.compact(statistics.totalSeconds)) of \(DurationText.compact(seconds))"
            case .skillSessionCount(let count):
                current = Double(statistics.sessionCount)
                target = Double(count)
                label = "\(min(statistics.sessionCount, count)) of \(count) sessions"
            case .longestSession(let seconds):
                current = Double(statistics.longestSeconds)
                target = Double(seconds)
                label = "Best: \(DurationText.compact(statistics.longestSeconds))"
            case .activeDays(let count):
                current = Double(statistics.activeDayCount)
                target = Double(count)
                label = "\(min(statistics.activeDayCount, count)) of \(count) days"
            case .returnAfterDays:
                current = didReturn ? 1 : 0
                target = 1
                label = didReturn ? "Returned" : "Not yet earned"
            case .activeWeeks(let count):
                current = Double(weeks)
                target = Double(count)
                label = "\(min(weeks, count)) of \(count) weeks"
            case .activeMonths(let count):
                current = Double(months)
                target = Double(count)
                label = "\(min(months, count)) of \(count) months"
            default:
                current = 0
                target = 1
                label = "Not applicable"
            }

            return AchievementStatus(
                definition: definition,
                skillID: skill.id,
                currentValue: current,
                targetValue: target,
                progressLabel: label
            )
        }
    }

    static func globalStatuses(skills: [LifeSkill], sessions: [SkillSession]) -> [AchievementStatus] {
        let totalLevel = SessionAnalytics.totalLevel(skills: skills, sessions: sessions)
        let totalSeconds = sessions.reduce(0) { $0 + max(0, $1.activeSeconds) }
        let activeSkillIDs = Set(sessions.filter { $0.activeSeconds > 0 }.map(\.skillID))

        return globalDefinitions.map { definition in
            let current: Double
            let target: Double
            let label: String

            switch definition.criterion {
            case .totalLevel(let value):
                current = Double(totalLevel)
                target = Double(value)
                label = "Total Level \(min(totalLevel, value)) of \(value)"
            case .activeSkillCount(let count):
                current = Double(activeSkillIDs.count)
                target = Double(count)
                label = "\(min(activeSkillIDs.count, count)) of \(count) Skills"
            case .globalDuration(let seconds):
                current = Double(totalSeconds)
                target = Double(seconds)
                label = "\(DurationText.compact(totalSeconds)) of \(DurationText.compact(seconds))"
            default:
                current = 0
                target = 1
                label = "Not applicable"
            }

            return AchievementStatus(
                definition: definition,
                skillID: nil,
                currentValue: current,
                targetValue: target,
                progressLabel: label
            )
        }
    }

    static func unlockedCount(skills: [LifeSkill], sessions: [SkillSession]) -> Int {
        let skillUnlocks = skills
            .flatMap { statuses(for: $0, sessions: sessions) }
            .filter(\.isUnlocked)
            .count
        let globalUnlocks = globalStatuses(skills: skills, sessions: sessions).filter(\.isUnlocked).count
        return skillUnlocks + globalUnlocks
    }

    private static func distinctWeekCount(in sessions: [SkillSession], calendar: Calendar) -> Int {
        Set(sessions.map { session in
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.creditedAt)
            return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
        }).count
    }

    private static func distinctMonthCount(in sessions: [SkillSession], calendar: Calendar) -> Int {
        Set(sessions.map { session in
            let components = calendar.dateComponents([.year, .month], from: session.creditedAt)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        }).count
    }

    private static func containsReturnGap(in sessions: [SkillSession], minimumDays: Int, calendar: Calendar) -> Bool {
        let sorted = sessions.sorted { $0.creditedAt < $1.creditedAt }
        guard sorted.count > 1 else { return false }

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]
            let days = calendar.dateComponents([.day], from: previous.endedAt, to: current.startedAt).day ?? 0
            if days >= minimumDays { return true }
        }
        return false
    }

    static func definition(id: String) -> AchievementDefinition? {
        (skillDefinitions + globalDefinitions).first { $0.id == id }
    }
}

enum DurationText {
    static func timer(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let remainder = safe % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
    }

    static func compact(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(safe)s"
    }
}
