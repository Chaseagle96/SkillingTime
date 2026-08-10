import ActivityKit
import Foundation

struct SkillingTimeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var accumulatedActiveSeconds: Int
        var activeSegmentStartedAt: Date?
        var baseTotalSeconds: Int
        var level: Int
        var rankName: String
        var xpEarned: Int
        var xpRemaining: Int
        var progressFraction: Double
        var focusGoalTitle: String?
        var focusGoalProgressLabel: String?
        var focusGoalFraction: Double?
        var questTitle: String?
        var questProgressLabel: String?
        var questFraction: Double?
        var questTimerStart: Date?
        var questTimerEnd: Date?
        var questIsComplete: Bool?
        var isPaused: Bool
        var isAwaitingCommit: Bool

        var effectiveTimerStart: Date? {
            guard let activeSegmentStartedAt, !isPaused else { return nil }
            return activeSegmentStartedAt.addingTimeInterval(
                TimeInterval(-max(0, accumulatedActiveSeconds))
            )
        }

        func elapsedSeconds(at date: Date = .now) -> Int {
            guard let activeSegmentStartedAt, !isPaused else {
                return max(0, accumulatedActiveSeconds)
            }
            return max(
                0,
                accumulatedActiveSeconds
                    + Int(max(0, date.timeIntervalSince(activeSegmentStartedAt)))
            )
        }
    }

    let sessionID: UUID
    let skillID: UUID
    let skillName: String
    let symbolName: String
    let accentHex: String
    let curveVersion: Int
}
