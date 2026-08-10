import ActivityKit
import AppIntents
import Foundation
import UserNotifications

struct ToggleSkillingTimeSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Skilling Time Session"
    static var description = IntentDescription(
        "Toggles the active Skilling Time timer without opening the app."
    )
    static var openAppWhenRun: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Session ID")
    var sessionID: String

    init() {
        sessionID = ""
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let actionDate = Date.now
        guard let id = UUID(uuidString: sessionID),
              let payload = SharedActiveSessionStore.togglePause(
                sessionID: id,
                at: actionDate
              )
        else { return .result() }

        guard let activity = Activity<SkillingTimeActivityAttributes>.activities.first(
            where: { $0.attributes.sessionID == id }
        ) else { return .result() }

        var state = activity.content.state
        state.accumulatedActiveSeconds = payload.accumulatedActiveSeconds
        state.activeSegmentStartedAt = payload.activeSegmentStartedAt
        state.isPaused = payload.isPaused
        state.isAwaitingCommit = payload.isAwaitingCommit
        refreshProgressionState(
            &state,
            payload: payload,
            attributes: activity.attributes,
            at: actionDate
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
        await synchronizeProgressionNotification(
            payload: payload,
            activity: activity,
            at: actionDate
        )
        return .result()
    }

    private func refreshProgressionState(
        _ state: inout SkillingTimeActivityAttributes.ContentState,
        payload: SharedActiveSessionPayload,
        attributes: SkillingTimeActivityAttributes,
        at date: Date
    ) {
        let sessionSeconds = payload.elapsedSeconds(at: date)
        let startingXP = ProgressionEngine.xp(
            forActiveSeconds: state.baseTotalSeconds,
            curveVersion: attributes.curveVersion
        )
        let liveXP = ProgressionEngine.xp(
            forActiveSeconds: state.baseTotalSeconds + sessionSeconds,
            curveVersion: attributes.curveVersion
        )
        let progress = ProgressionEngine.progress(
            forTotalXP: liveXP,
            curveVersion: attributes.curveVersion
        )

        state.level = progress.level
        state.rankName = progress.displayRank
        state.xpEarned = max(0, liveXP - startingXP)
        state.xpRemaining = progress.xpRemaining
        state.progressFraction = progress.fractionComplete

        guard let goal = payload.focusGoal else {
            state.focusGoalTitle = nil
            state.focusGoalProgressLabel = nil
            state.focusGoalFraction = nil
            return
        }

        let current: Int
        let target: Int
        let title: String
        let label: String

        switch goal.kind {
        case "duration":
            current = max(0, sessionSeconds)
            target = max(1, goal.targetValue)
            title = "Practice for \(compactDuration(target))"
            label = "\(compactDuration(min(current, target))) of \(compactDuration(target))"
        case "xp":
            current = max(0, liveXP - goal.startingTotalXP)
            target = max(1, goal.targetValue)
            title = "Earn \(target.formatted()) XP"
            label = "\(min(current, target).formatted()) of \(target.formatted()) XP"
        case "progression":
            current = max(0, liveXP - goal.startingTotalXP)
            target = max(1, goal.targetValue - goal.startingTotalXP)
            title = "Reach the next progression threshold"
            label = "\(min(current, target).formatted()) of \(target.formatted()) XP"
        default:
            state.focusGoalTitle = nil
            state.focusGoalProgressLabel = nil
            state.focusGoalFraction = nil
            return
        }

        state.focusGoalTitle = title
        state.focusGoalProgressLabel = label
        state.focusGoalFraction = min(max(Double(current) / Double(target), 0), 1)
    }

    private func compactDuration(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3_600
        let minutes = (safe % 3_600) / 60
        let remainder = safe % 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return remainder > 0 ? "\(minutes)m \(remainder)s" : "\(minutes)m" }
        return "\(remainder)s"
    }

    private func synchronizeProgressionNotification(
        payload: SharedActiveSessionPayload,
        activity: Activity<SkillingTimeActivityAttributes>,
        at date: Date
    ) async {
        let center = UNUserNotificationCenter.current()
        let identifier = SkillingTimeSharedConfiguration.progressionNotificationIdentifier
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let defaults = SkillingTimeSharedConfiguration.makeSharedDefaults()
        guard !payload.isPaused,
              defaults.bool(forKey: SkillingTimeSharedConfiguration.notificationPreferenceKey)
        else { return }

        let settings = await center.notificationSettings()
        guard [
            UNAuthorizationStatus.authorized,
            .provisional,
            .ephemeral
        ].contains(settings.authorizationStatus) else { return }

        let attributes = activity.attributes
        let currentTotalSeconds = activity.content.state.baseTotalSeconds
            + payload.elapsedSeconds(at: date)
        let currentXP = ProgressionEngine.xp(
            forActiveSeconds: currentTotalSeconds,
            curveVersion: attributes.curveVersion
        )
        let progress = ProgressionEngine.progress(
            forTotalXP: currentXP,
            curveVersion: attributes.curveVersion
        )
        let targetXP = ProgressionEngine.nextThresholdXP(
            after: progress,
            curveVersion: attributes.curveVersion
        )
        let targetSeconds = targetXP * ProgressionEngine.secondsPerXP(
            curveVersion: attributes.curveVersion
        )
        let remainingSeconds = max(1, targetSeconds - currentTotalSeconds)
        let destination = progress.level < ProgressionEngine.maximumLevel(
            curveVersion: attributes.curveVersion
        )
            ? "Level \(progress.level + 1)"
            : "Mastery star \(progress.masteryStars + 1)"

        let content = UNMutableNotificationContent()
        content.title = "\(attributes.skillName) increased"
        content.body = "Your active session reached \(destination). Return to keep progressing."
        content.sound = .default
        content.threadIdentifier = "skillingtime-progression"
        content.userInfo = [
            "skillID": attributes.skillID.uuidString,
            "sessionID": payload.id.uuidString,
            "targetTotalXP": targetXP
        ]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(remainingSeconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            // The timer action already succeeded; the app will retry alert sync next launch.
        }
    }
}
