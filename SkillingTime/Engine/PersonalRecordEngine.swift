import Foundation
import SwiftData

enum PersonalRecordKind: String, Codable, Sendable {
    case longestSkillSession
    case mostTimeInDay
    case highestXPDay
    case bestWeek

    var systemImage: String {
        switch self {
        case .longestSkillSession: "stopwatch.fill"
        case .mostTimeInDay: "sun.max.fill"
        case .highestXPDay: "sparkles"
        case .bestWeek: "calendar.badge.checkmark"
        }
    }
}

struct PersonalRecordReveal: Identifiable, Sendable {
    let id: String
    let kind: PersonalRecordKind
    let skillID: UUID?
    let title: String
    let description: String
    let value: Int
    let previousValue: Int
    let achievedAt: Date
    let triggeringSessionID: UUID

    var systemImage: String { kind.systemImage }
}

@MainActor
enum PersonalRecordEngine {
    static func newRecords(
        triggeringSession: SkillSession,
        beforeSessions: [SkillSession],
        afterSessions: [SkillSession],
        skills: [LifeSkill],
        calendar: Calendar = .current
    ) -> [PersonalRecordReveal] {
        var results: [PersonalRecordReveal] = []
        let skill = skills.first { $0.id == triggeringSession.skillID }

        let previousSkillLongest = beforeSessions
            .filter { $0.skillID == triggeringSession.skillID }
            .map(\.activeSeconds)
            .max() ?? 0
        if previousSkillLongest > 0,
           triggeringSession.activeSeconds > previousSkillLongest {
            results.append(
                reveal(
                    kind: .longestSkillSession,
                    skillID: triggeringSession.skillID,
                    title: "Longest \(skill?.name ?? "Skill") Session",
                    description: "\(DurationText.compact(triggeringSession.activeSeconds)) · previous best \(DurationText.compact(previousSkillLongest))",
                    value: triggeringSession.activeSeconds,
                    previousValue: previousSkillLongest,
                    session: triggeringSession
                )
            )
        }

        let beforeDays = ActivityDayLedgerService.makeAggregates(
            skills: skills,
            sessions: beforeSessions,
            calendar: calendar
        )
        let afterDays = ActivityDayLedgerService.makeAggregates(
            skills: skills,
            sessions: afterSessions,
            calendar: calendar
        )
        let triggerDay = calendar.startOfDay(for: triggeringSession.creditedAt)
        if let afterDay = afterDays.first(where: {
            calendar.isDate($0.dayStart, inSameDayAs: triggerDay)
        }) {
            let previousTimeBest = beforeDays.map(\.totalActiveSeconds).max() ?? 0
            if previousTimeBest > 0, afterDay.totalActiveSeconds > previousTimeBest {
                results.append(
                    reveal(
                        kind: .mostTimeInDay,
                        skillID: nil,
                        title: "Most Skilling Time in One Day",
                        description: "\(DurationText.compact(afterDay.totalActiveSeconds)) · previous best \(DurationText.compact(previousTimeBest))",
                        value: afterDay.totalActiveSeconds,
                        previousValue: previousTimeBest,
                        session: triggeringSession
                    )
                )
            }

            let previousXPBest = beforeDays.map(\.xpEarned).max() ?? 0
            if previousXPBest > 0, afterDay.xpEarned > previousXPBest {
                results.append(
                    reveal(
                        kind: .highestXPDay,
                        skillID: nil,
                        title: "Highest XP Day",
                        description: "\(afterDay.xpEarned.formatted()) XP · previous best \(previousXPBest.formatted()) XP",
                        value: afterDay.xpEarned,
                        previousValue: previousXPBest,
                        session: triggeringSession
                    )
                )
            }
        }

        let beforeWeeks = weeklyTotals(sessions: beforeSessions, calendar: calendar)
        let afterWeeks = weeklyTotals(sessions: afterSessions, calendar: calendar)
        let triggerWeek = calendar.dateInterval(
            of: .weekOfYear,
            for: triggeringSession.creditedAt
        )?.start
        if let triggerWeek,
           let afterWeek = afterWeeks.first(where: { $0.key == triggerWeek })?.value {
            let previousWeekBest = beforeWeeks.values.max() ?? 0
            if previousWeekBest > 0, afterWeek > previousWeekBest {
                results.append(
                    reveal(
                        kind: .bestWeek,
                        skillID: nil,
                        title: "Best Week",
                        description: "\(DurationText.compact(afterWeek)) · previous best \(DurationText.compact(previousWeekBest))",
                        value: afterWeek,
                        previousValue: previousWeekBest,
                        session: triggeringSession
                    )
                )
            }
        }

        return results
    }

    private static func reveal(
        kind: PersonalRecordKind,
        skillID: UUID?,
        title: String,
        description: String,
        value: Int,
        previousValue: Int,
        session: SkillSession
    ) -> PersonalRecordReveal {
        let scope = skillID?.uuidString.lowercased() ?? "global"
        return PersonalRecordReveal(
            id: "\(kind.rawValue)|\(scope)|\(session.id.uuidString.lowercased())",
            kind: kind,
            skillID: skillID,
            title: title,
            description: description,
            value: value,
            previousValue: previousValue,
            achievedAt: session.creditedAt,
            triggeringSessionID: session.id
        )
    }

    private static func weeklyTotals(
        sessions: [SkillSession],
        calendar: Calendar
    ) -> [Date: Int] {
        var totals: [Date: Int] = [:]
        for session in sessions {
            guard let weekStart = calendar.dateInterval(
                of: .weekOfYear,
                for: session.creditedAt
            )?.start else { continue }
            totals[weekStart, default: 0] += max(0, session.activeSeconds)
        }
        return totals
    }
}

@MainActor
enum PersonalRecordReconciler {
    static func insertNew(
        _ reveals: [PersonalRecordReveal],
        existingRecords: [PersonalRecordEvent],
        in modelContext: ModelContext
    ) -> [PersonalRecordReveal] {
        let existingIDs = Set(existingRecords.map(\.id))
        let fresh = reveals.filter { !existingIDs.contains($0.id) }
        for reveal in fresh {
            modelContext.insert(
                PersonalRecordEvent(
                    id: reveal.id,
                    kindRawValue: reveal.kind.rawValue,
                    skillID: reveal.skillID,
                    title: reveal.title,
                    recordDescription: reveal.description,
                    value: reveal.value,
                    previousValue: reveal.previousValue,
                    achievedAt: reveal.achievedAt,
                    triggeringSessionID: reveal.triggeringSessionID
                )
            )
        }
        return fresh
    }
}
