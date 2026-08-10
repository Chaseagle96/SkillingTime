import Foundation

struct QuestStatus: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let systemImage: String
    let currentValue: Double
    let targetValue: Double
    let progressLabel: String

    var isComplete: Bool { currentValue >= targetValue }
    var fractionComplete: Double {
        guard targetValue > 0 else { return 1 }
        return min(max(currentValue / targetValue, 0), 1)
    }
}

enum QuestEngine {
    static func currentQuests(sessions: [SkillSession], calendar: Calendar = .current, now: Date = .now) -> [QuestStatus] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let todaySessions = sessions.filter { $0.creditedAt >= startOfToday && $0.creditedAt <= now }
        let weekSessions = sessions.filter { $0.creditedAt >= startOfWeek && $0.creditedAt <= now }

        let todaySeconds = todaySessions.reduce(0) { $0 + $1.activeSeconds }
        let weekSeconds = weekSessions.reduce(0) { $0 + $1.activeSeconds }
        let weekSkills = Set(weekSessions.map(\.skillID)).count
        let weekSessionCount = weekSessions.count

        return [
            QuestStatus(
                id: "daily-practice",
                title: "A Little Progress",
                description: "Invest 20 minutes in any Skill today.",
                systemImage: "sun.max.fill",
                currentValue: Double(todaySeconds),
                targetValue: Double(20 * 60),
                progressLabel: "\(DurationText.compact(todaySeconds)) of 20m"
            ),
            QuestStatus(
                id: "weekly-dedication",
                title: "Weekly Dedication",
                description: "Record two hours across your Skillbook this week.",
                systemImage: "calendar.badge.clock",
                currentValue: Double(weekSeconds),
                targetValue: Double(2 * 3600),
                progressLabel: "\(DurationText.compact(weekSeconds)) of 2h"
            ),
            QuestStatus(
                id: "many-paths",
                title: "Walk Three Paths",
                description: "Practice three different Skills this week.",
                systemImage: "arrow.triangle.branch",
                currentValue: Double(weekSkills),
                targetValue: 3,
                progressLabel: "\(min(weekSkills, 3)) of 3 Skills"
            ),
            QuestStatus(
                id: "return-often",
                title: "Return Often",
                description: "Complete three sessions this week.",
                systemImage: "repeat.circle.fill",
                currentValue: Double(weekSessionCount),
                targetValue: 3,
                progressLabel: "\(min(weekSessionCount, 3)) of 3 sessions"
            )
        ]
    }
}
