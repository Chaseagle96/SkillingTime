import ActivityKit
import AppIntents
import Foundation
import UserNotifications

struct ToggleSkillingTimeSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Skilling Time Session"
    static let description = IntentDescription(
        "Toggles the active Skilling Time timer without opening the app."
    )
    static var openAppWhenRun: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    /// Only meaningful from the Live Activity's own button; keep it out of Shortcuts.
    static var isDiscoverable: Bool { false }

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
            where: {
                $0.attributes.sessionID == id
                    && ($0.activityState == .active || $0.activityState == .stale)
            }
        ) else { return .result() }

        var state = activity.content.state
        let wasPaused = state.isPaused
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
        refreshQuestTimer(&state, wasPaused: wasPaused, at: actionDate)
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

        guard let goal = payload.focusGoal?.goal else {
            state.focusGoalTitle = nil
            state.focusGoalProgressLabel = nil
            state.focusGoalFraction = nil
            return
        }

        let evaluated = FocusGoalProgress.evaluate(
            goal: goal,
            sessionSeconds: sessionSeconds,
            liveTotalXP: liveXP
        )
        state.focusGoalTitle = evaluated.title
        state.focusGoalProgressLabel = evaluated.progressLabel
        state.focusGoalFraction = evaluated.fractionComplete
    }

    /// Time-based quest countdowns are an interval that only runs while the timer
    /// runs. Pausing freezes the reached fraction; resuming re-anchors the interval
    /// at the resume instant so paused time is not counted.
    private func refreshQuestTimer(
        _ state: inout SkillingTimeActivityAttributes.ContentState,
        wasPaused: Bool,
        at date: Date
    ) {
        guard let start = state.questTimerStart,
              let end = state.questTimerEnd,
              start < end,
              state.questIsComplete != true else { return }
        let duration = end.timeIntervalSince(start)

        if state.isPaused, !wasPaused {
            let reached = min(max(date.timeIntervalSince(start), 0), duration)
            state.questFraction = reached / duration
            state.questProgressLabel = questLabel(reached: reached, duration: duration)
        } else if !state.isPaused, wasPaused {
            let reached = min(max((state.questFraction ?? 0) * duration, 0), duration)
            let newStart = date.addingTimeInterval(-reached)
            state.questTimerStart = newStart
            state.questTimerEnd = newStart.addingTimeInterval(duration)
            state.questProgressLabel = questLabel(reached: reached, duration: duration)
        }
    }

    private func questLabel(reached: TimeInterval, duration: TimeInterval) -> String {
        "\(DurationText.compact(Int(reached))) of \(DurationText.compact(Int(duration.rounded())))"
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
