import Foundation

enum SkillingTimeSharedConfiguration {
    // Legacy identifiers are intentionally retained so the rename is an in-place
    // upgrade and existing active-session / notification state remains recoverable.
    static let appGroupIdentifier = "group.com.projectskillbook.app"
    static let activeSessionKey = "skillbook.active-session.v2"
    static let legacyActiveSessionKey = "skillbook.active-session.v1"
    static let notificationPreferenceKey = "skillbook.progression-alerts.enabled"
    static let progressionNotificationIdentifier = "skillbook.progression.next-threshold"

    static func makeSharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

/// Codable mirror used by the Live Activity intent without importing the app target.
struct SharedSessionFocusGoalPayload: Codable, Equatable, Sendable {
    let kind: String
    let targetValue: Int
    let startingTotalXP: Int
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
