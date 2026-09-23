import Foundation

enum SkillingTimeSharedConfiguration {
    // Legacy identifiers are intentionally retained so the rename is an in-place
    // upgrade and existing active-session / notification state remains recoverable.
    static let appGroupIdentifier = "group.com.projectskillbook.app"
    static let activeSessionKey = "skillbook.active-session.v2"
    static let legacyActiveSessionKey = "skillbook.active-session.v1"
    static let unreadableActiveSessionKey = "skillbook.active-session.unreadable"
    static let notificationPreferenceKey = "skillbook.progression-alerts.enabled"
    static let progressionNotificationIdentifier = "skillbook.progression.next-threshold"

    /// `UserDefaults(suiteName:)` returns a store even when the App Group is not
    /// entitled (for example after a re-signing tool renames the group). That store
    /// is not shared, so check the group container before relying on it.
    static func makeSharedDefaults() -> UserDefaults {
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) != nil,
            let shared = UserDefaults(suiteName: appGroupIdentifier)
        else {
            return .standard
        }
        return shared
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

    /// Like `compact`, but keeps seconds under an hour so two close values (for
    /// example 61s and 119s) don't both read as "1m".
    static func precise(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        guard safe < 3600 else { return compact(safe) }
        let minutes = safe / 60
        let remainder = safe % 60
        if minutes == 0 { return "\(remainder)s" }
        return remainder > 0 ? "\(minutes)m \(remainder)s" : "\(minutes)m"
    }
}

enum SessionFocusGoalKind: String, Codable, CaseIterable, Sendable {
    case duration
    case xp
    case progression
}

struct SessionFocusGoal: Codable, Equatable, Sendable {
    let kind: SessionFocusGoalKind
    let targetValue: Int
    let startingTotalXP: Int

    static func duration(seconds: Int, startingTotalXP: Int) -> SessionFocusGoal {
        SessionFocusGoal(kind: .duration, targetValue: max(1, seconds), startingTotalXP: startingTotalXP)
    }

    static func xp(amount: Int, startingTotalXP: Int) -> SessionFocusGoal {
        SessionFocusGoal(kind: .xp, targetValue: max(1, amount), startingTotalXP: startingTotalXP)
    }

    static func progression(targetTotalXP: Int, startingTotalXP: Int) -> SessionFocusGoal {
        SessionFocusGoal(
            kind: .progression,
            targetValue: max(startingTotalXP + 1, targetTotalXP),
            startingTotalXP: startingTotalXP
        )
    }
}

struct FocusGoalProgress: Equatable, Sendable {
    let title: String
    let currentValue: Int
    let targetValue: Int
    let progressLabel: String
    let fractionComplete: Double
    let isComplete: Bool

    static func evaluate(
        goal: SessionFocusGoal,
        sessionSeconds: Int,
        liveTotalXP: Int
    ) -> FocusGoalProgress {
        let current: Int
        let target: Int
        let title: String
        let label: String

        switch goal.kind {
        case .duration:
            current = max(0, sessionSeconds)
            target = goal.targetValue
            title = "Practice for \(DurationText.compact(target))"
            label = "\(DurationText.compact(min(current, target))) of \(DurationText.compact(target))"
        case .xp:
            current = max(0, liveTotalXP - goal.startingTotalXP)
            target = goal.targetValue
            title = "Earn \(target.formatted()) XP"
            label = "\(min(current, target).formatted()) of \(target.formatted()) XP"
        case .progression:
            current = max(0, liveTotalXP - goal.startingTotalXP)
            target = max(1, goal.targetValue - goal.startingTotalXP)
            title = "Reach the next progression threshold"
            label = "\(min(current, target).formatted()) of \(target.formatted()) XP"
        }

        let fraction = min(max(Double(current) / Double(max(1, target)), 0), 1)
        return FocusGoalProgress(
            title: title,
            currentValue: current,
            targetValue: target,
            progressLabel: label,
            fractionComplete: fraction,
            isComplete: current >= target
        )
    }
}

/// Codable mirror used by the Live Activity intent without importing the app target.
struct SharedSessionFocusGoalPayload: Codable, Equatable, Sendable {
    let kind: String
    let targetValue: Int
    let startingTotalXP: Int

    var goal: SessionFocusGoal? {
        guard let kind = SessionFocusGoalKind(rawValue: kind) else { return nil }
        return SessionFocusGoal(
            kind: kind,
            targetValue: targetValue,
            startingTotalXP: startingTotalXP
        )
    }
}

/// Its coding keys intentionally match `ActiveSessionSnapshot` exactly.
struct SharedActiveSessionPayload: Codable, Equatable, Sendable {
    let id: UUID
    let skillID: UUID
    let startedAt: Date
    var accumulatedActiveSeconds: Int
    var activeSegmentStartedAt: Date?
    var finishRequestedAt: Date?
    var shouldResumeAfterCancelledFinish: Bool?
    var focusGoal: SharedSessionFocusGoalPayload?

    var isPaused: Bool { activeSegmentStartedAt == nil }
    var isAwaitingCommit: Bool { finishRequestedAt != nil }

    func elapsedSeconds(at date: Date = .now) -> Int {
        guard let segmentStart = activeSegmentStartedAt else {
            return max(0, accumulatedActiveSeconds)
        }
        return max(
            0,
            accumulatedActiveSeconds + Int(max(0, date.timeIntervalSince(segmentStart)))
        )
    }
}

enum SharedActiveSessionStore {
    static func load(from defaults: UserDefaults) -> SharedActiveSessionPayload? {
        guard let data = defaults.data(forKey: SkillingTimeSharedConfiguration.activeSessionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SharedActiveSessionPayload.self, from: data)
    }

    @discardableResult
    static func save(
        _ session: SharedActiveSessionPayload,
        to defaults: UserDefaults
    ) -> Bool {
        do {
            defaults.set(try JSONEncoder().encode(session), forKey: SkillingTimeSharedConfiguration.activeSessionKey)
            return true
        } catch {
            return false
        }
    }

    static func togglePause(
        sessionID: UUID,
        at date: Date = .now,
        defaults: UserDefaults = SkillingTimeSharedConfiguration.makeSharedDefaults()
    ) -> SharedActiveSessionPayload? {
        guard var session = load(from: defaults),
              session.id == sessionID,
              !session.isAwaitingCommit else { return nil }

        if session.isPaused {
            session.activeSegmentStartedAt = date
        } else {
            session.accumulatedActiveSeconds = session.elapsedSeconds(at: date)
            session.activeSegmentStartedAt = nil
        }
        guard save(session, to: defaults) else { return nil }
        return session
    }
}
