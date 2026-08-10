import Foundation
import SwiftData

/// Maintains rebuildable aggregates without changing the authority of session history.
@MainActor
enum SkillLedgerService {
    /// Performs a cheap count/invariant check and scans history only when the cache is absent or stale.
    @discardableResult
    static func rebuildIfNeeded(
        in modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws -> Bool {
        do {
            let sessionCount = try modelContext.fetchCount(FetchDescriptor<SkillSession>())
            let ledgers = try modelContext.fetch(FetchDescriptor<SkillLedger>())
            let cachedSessionCount = ledgers.reduce(0) {
                $0 + max(0, $1.sessionCount)
            }
            let hasInvalidLedger = ledgers.contains {
                $0.sessionCount <= 0
                    || $0.totalActiveSeconds < 0
                    || $0.longestSessionSeconds < 0
                    || $0.activeDayCount < 0
            }

            guard cachedSessionCount != sessionCount || hasInvalidLedger else {
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
            let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
            let ledgers = try modelContext.fetch(FetchDescriptor<SkillLedger>())
            let sessionsBySkill = Dictionary(grouping: sessions, by: \.skillID)
            let existingBySkill = Dictionary(uniqueKeysWithValues: ledgers.map { ($0.skillID, $0) })
            let skillIDs = Set(sessionsBySkill.keys).union(existingBySkill.keys)

            for skillID in skillIDs {
                reconcile(
                    skillID: skillID,
                    matchingSessions: sessionsBySkill[skillID] ?? [],
                    existingLedger: existingBySkill[skillID],
                    in: modelContext,
                    calendar: calendar,
                    now: now
                )
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func reconcile(
        skillID: UUID,
        sessions: [SkillSession],
        existingLedgers: [SkillLedger],
        in modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        reconcile(
            skillID: skillID,
            matchingSessions: sessions.filter { $0.skillID == skillID },
            existingLedger: existingLedgers.first { $0.skillID == skillID },
            in: modelContext,
            calendar: calendar,
            now: now
        )
    }

    private static func reconcile(
        skillID: UUID,
        matchingSessions: [SkillSession],
        existingLedger: SkillLedger?,
        in modelContext: ModelContext,
        calendar: Calendar,
        now: Date
    ) {
        guard !matchingSessions.isEmpty else {
            if let existingLedger {
                modelContext.delete(existingLedger)
            }
            return
        }

        let statistics = SessionAnalytics.statistics(
            for: skillID,
            sessions: matchingSessions,
            calendar: calendar
        )
        let ledger = existingLedger ?? SkillLedger(skillID: skillID)

        if existingLedger == nil {
            modelContext.insert(ledger)
        }

        ledger.totalActiveSeconds = statistics.totalSeconds
        ledger.sessionCount = statistics.sessionCount
        ledger.longestSessionSeconds = statistics.longestSeconds
        ledger.activeDayCount = statistics.activeDayCount
        ledger.firstSessionAt = statistics.firstSessionDate
        ledger.latestSessionAt = statistics.latestSessionDate
        ledger.rebuiltAt = now
    }
}
