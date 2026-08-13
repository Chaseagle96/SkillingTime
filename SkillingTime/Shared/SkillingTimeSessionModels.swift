import Foundation

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

/// The single persisted representation of a running Skilling session.
///
/// This file is intentionally Foundation-only so the same timestamp and pause
/// semantics can be consumed by the iPhone, Watch, and Live Activity targets.
struct ActiveSessionSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let skillID: UUID
    let startedAt: Date
    var accumulatedActiveSeconds: Int
    var activeSegmentStartedAt: Date?
    var finishRequestedAt: Date?
    var shouldResumeAfterCancelledFinish: Bool?
    var focusGoal: SessionFocusGoal?

    var isPaused: Bool { activeSegmentStartedAt == nil }
    var isAwaitingCommit: Bool { finishRequestedAt != nil }

    func elapsedSeconds(at date: Date = .now) -> Int {
        guard let segmentStart = activeSegmentStartedAt else {
            return max(0, accumulatedActiveSeconds)
        }

        let currentSegment = max(0, Int(date.timeIntervalSince(segmentStart)))
        return max(0, accumulatedActiveSeconds + currentSegment)
    }
}

struct CompletedSessionDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let skillID: UUID
    let startedAt: Date
    let endedAt: Date
    let activeSeconds: Int
    let focusGoal: SessionFocusGoal?
    let shouldResumeOnCancel: Bool
}
