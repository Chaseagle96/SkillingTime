import Foundation
import SwiftData

struct ActivityDayAggregate: Sendable {
    let id: String
    let dayStart: Date
    let timeZoneIdentifier: String
    var totalActiveSeconds: Int = 0
    var xpEarned: Int = 0
    var sessionCount: Int = 0
    var skillIDs: Set<UUID> = []
    var longestSessionSeconds: Int = 0
}

/// Builds calendar summaries from authoritative sessions. Day rows are disposable cache data.
@MainActor
enum ActivityDayLedgerService {
    @discardableResult
    static func rebuildIfNeeded(
        in modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws -> Bool {
        do {
            let sessionCount = try modelContext.fetchCount(FetchDescriptor<SkillSession>())
            let dayLedgers = try modelContext.fetch(FetchDescriptor<ActivityDayLedger>())
            let cachedSessionCount = dayLedgers.reduce(0) { $0 + max(0, $1.sessionCount) }
            let hasInvalidRow = dayLedgers.contains {
                $0.totalActiveSeconds < 0
                    || $0.xpEarned < 0
                    || $0.sessionCount <= 0
                    || $0.distinctSkillCount <= 0
                    || $0.longestSessionSeconds < 0
                    || $0.timeZoneIdentifier != calendar.timeZone.identifier
            }

            guard cachedSessionCount != sessionCount || hasInvalidRow else {
                return false
            }

            try rebuildAll(in: modelContext, calendar: calendar, now: now)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func rebuildAll(
        in modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws {
        do {
            let skills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
            let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
            let dayLedgers = try modelContext.fetch(FetchDescriptor<ActivityDayLedger>())
            reconcile(
                skills: skills,
                sessions: sessions,
                existingLedgers: dayLedgers,
                in: modelContext,
                calendar: calendar,
                now: now
            )
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func reconcile(
        skills: [LifeSkill],
        sessions: [SkillSession],
        existingLedgers: [ActivityDayLedger],
        in modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        let aggregates = makeAggregates(
            skills: skills,
            sessions: sessions,
            calendar: calendar
        )
        let aggregateByID = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.id, $0) })
        let existingByID = Dictionary(uniqueKeysWithValues: existingLedgers.map { ($0.id, $0) })

        for ledger in existingLedgers where aggregateByID[ledger.id] == nil {
            modelContext.delete(ledger)
        }

        for aggregate in aggregates {
            let ledger = existingByID[aggregate.id] ?? ActivityDayLedger(
                id: aggregate.id,
                dayStart: aggregate.dayStart,
                timeZoneIdentifier: aggregate.timeZoneIdentifier
            )
            if existingByID[aggregate.id] == nil {
                modelContext.insert(ledger)
            }

            ledger.dayStart = aggregate.dayStart
            ledger.timeZoneIdentifier = aggregate.timeZoneIdentifier
            ledger.totalActiveSeconds = aggregate.totalActiveSeconds
            ledger.xpEarned = aggregate.xpEarned
            ledger.sessionCount = aggregate.sessionCount
            ledger.distinctSkillCount = aggregate.skillIDs.count
            ledger.longestSessionSeconds = aggregate.longestSessionSeconds
            ledger.rebuiltAt = now
        }
    }

    static func makeAggregates(
        skills: [LifeSkill],
        sessions: [SkillSession],
        calendar: Calendar = .current
    ) -> [ActivityDayAggregate] {
        let skillsByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        let orderedSessions = sessions.sorted(by: sessionOrder)
        var cumulativeSecondsBySkill: [UUID: Int] = [:]
        var aggregatesByID: [String: ActivityDayAggregate] = [:]

        for session in orderedSessions {
            let safeSeconds = max(0, session.activeSeconds)
            let beforeSeconds = cumulativeSecondsBySkill[session.skillID, default: 0]
            let afterSeconds = beforeSeconds + safeSeconds
            cumulativeSecondsBySkill[session.skillID] = afterSeconds

            let xpDelta: Int
            if let skill = skillsByID[session.skillID] {
                let beforeXP = ProgressionEngine.xp(
                    forActiveSeconds: beforeSeconds,
                    curveVersion: skill.progressionCurveVersion
                )
                let afterXP = ProgressionEngine.xp(
                    forActiveSeconds: afterSeconds,
                    curveVersion: skill.progressionCurveVersion
                )
                xpDelta = max(0, afterXP - beforeXP)
            } else {
                xpDelta = 0
            }

            let dayStart = calendar.startOfDay(for: session.creditedAt)
            let id = identifier(for: dayStart, calendar: calendar)
            var aggregate = aggregatesByID[id] ?? ActivityDayAggregate(
                id: id,
                dayStart: dayStart,
                timeZoneIdentifier: calendar.timeZone.identifier
            )
            aggregate.totalActiveSeconds += safeSeconds
            aggregate.xpEarned += xpDelta
            aggregate.sessionCount += 1
            aggregate.skillIDs.insert(session.skillID)
            aggregate.longestSessionSeconds = max(
                aggregate.longestSessionSeconds,
                safeSeconds
            )
            aggregatesByID[id] = aggregate
        }

        return aggregatesByID.values.sorted { $0.dayStart < $1.dayStart }
    }

    static func identifier(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%@|%04d-%02d-%02d",
            calendar.timeZone.identifier,
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func sessionOrder(_ lhs: SkillSession, _ rhs: SkillSession) -> Bool {
        if lhs.creditedAt != rhs.creditedAt {
            return lhs.creditedAt < rhs.creditedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
