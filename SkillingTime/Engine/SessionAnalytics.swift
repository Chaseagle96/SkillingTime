import Foundation

struct SkillStatistics: Equatable, Sendable {
    let totalSeconds: Int
    let sessionCount: Int
    let averageSeconds: Int
    let longestSeconds: Int
    let activeDayCount: Int
    let firstSessionDate: Date?
    let latestSessionDate: Date?

    static let empty = SkillStatistics(
        totalSeconds: 0,
        sessionCount: 0,
        averageSeconds: 0,
        longestSeconds: 0,
        activeDayCount: 0,
        firstSessionDate: nil,
        latestSessionDate: nil
    )
}

struct SessionIndex: Sendable {
    let statisticsBySkill: [UUID: SkillStatistics]
    let totalSeconds: Int
    let sessionCount: Int

    func statistics(for skillID: UUID) -> SkillStatistics {
        statisticsBySkill[skillID] ?? .empty
    }
}

enum SessionAnalytics {
    static func sessions(for skillID: UUID, in sessions: [SkillSession]) -> [SkillSession] {
        sessions.filter { $0.skillID == skillID }
    }

    static func index(
        sessions: [SkillSession],
        calendar: Calendar = .current
    ) -> SessionIndex {
        let grouped = Dictionary(grouping: sessions, by: \.skillID)
        var statisticsBySkill: [UUID: SkillStatistics] = [:]
        statisticsBySkill.reserveCapacity(grouped.count)

        for (skillID, matching) in grouped {
            statisticsBySkill[skillID] = statistics(
                forMatchingSessions: matching,
                calendar: calendar
            )
        }

        return SessionIndex(
            statisticsBySkill: statisticsBySkill,
            totalSeconds: sessions.reduce(0) { $0 + max(0, $1.activeSeconds) },
            sessionCount: sessions.count
        )
    }

    static func index(ledgers: [SkillLedger]) -> SessionIndex {
        var statisticsBySkill: [UUID: SkillStatistics] = [:]
        statisticsBySkill.reserveCapacity(ledgers.count)

        for ledger in ledgers {
            statisticsBySkill[ledger.skillID] = SkillStatistics(
                totalSeconds: max(0, ledger.totalActiveSeconds),
                sessionCount: max(0, ledger.sessionCount),
                averageSeconds: ledger.sessionCount > 0
                    ? max(0, ledger.totalActiveSeconds) / ledger.sessionCount
                    : 0,
                longestSeconds: max(0, ledger.longestSessionSeconds),
                activeDayCount: max(0, ledger.activeDayCount),
                firstSessionDate: ledger.firstSessionAt,
                latestSessionDate: ledger.latestSessionAt
            )
        }

        return SessionIndex(
            statisticsBySkill: statisticsBySkill,
            totalSeconds: ledgers.reduce(0) { $0 + max(0, $1.totalActiveSeconds) },
            sessionCount: ledgers.reduce(0) { $0 + max(0, $1.sessionCount) }
        )
    }

    static func statistics(
        for skillID: UUID,
        sessions: [SkillSession],
        calendar: Calendar = .current
    ) -> SkillStatistics {
        statistics(
            forMatchingSessions: self.sessions(for: skillID, in: sessions),
            calendar: calendar
        )
    }

    static func totalSeconds(for skillID: UUID, sessions: [SkillSession]) -> Int {
        self.sessions(for: skillID, in: sessions).reduce(0) {
            $0 + max(0, $1.activeSeconds)
        }
    }

    static func totalXP(for skill: LifeSkill, sessions: [SkillSession]) -> Int {
        ProgressionEngine.xp(
            forActiveSeconds: totalSeconds(for: skill.id, sessions: sessions),
            curveVersion: skill.progressionCurveVersion
        )
    }

    static func totalLevel(
        skills: [LifeSkill],
        sessions: [SkillSession]
    ) -> Int {
        totalLevel(skills: skills, index: index(sessions: sessions))
    }

    static func totalLevel(skills: [LifeSkill], index: SessionIndex) -> Int {
        skills.reduce(0) { total, skill in
            let seconds = index.statistics(for: skill.id).totalSeconds
            let xp = ProgressionEngine.xp(
                forActiveSeconds: seconds,
                curveVersion: skill.progressionCurveVersion
            )
            return total + ProgressionEngine.level(
                forTotalXP: xp,
                curveVersion: skill.progressionCurveVersion
            )
        }
    }

    static func progress(for skill: LifeSkill, index: SessionIndex) -> ProgressSnapshot {
        let seconds = index.statistics(for: skill.id).totalSeconds
        let xp = ProgressionEngine.xp(
            forActiveSeconds: seconds,
            curveVersion: skill.progressionCurveVersion
        )
        return ProgressionEngine.progress(
            forTotalXP: xp,
            curveVersion: skill.progressionCurveVersion
        )
    }

    private static func statistics(
        forMatchingSessions matching: [SkillSession],
        calendar: Calendar
    ) -> SkillStatistics {
        guard !matching.isEmpty else { return .empty }

        let total = matching.reduce(0) { $0 + max(0, $1.activeSeconds) }
        let days = Set(matching.map { calendar.startOfDay(for: $0.creditedAt) })
        let dates = matching.map(\.creditedAt)

        return SkillStatistics(
            totalSeconds: total,
            sessionCount: matching.count,
            averageSeconds: total / matching.count,
            longestSeconds: matching.map(\.activeSeconds).max() ?? 0,
            activeDayCount: days.count,
            firstSessionDate: dates.min(),
            latestSessionDate: dates.max()
        )
    }
}
