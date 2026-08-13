import ActivityKit
import Combine
import Foundation
import OSLog

/// Owns the app-to-ActivityKit boundary for the current recoverable session.
///
/// SwiftUI views can appear and disappear while a session continues. Activity
/// lifecycle work therefore lives here, and requests are serialized so an
/// older launch/navigation reconciliation cannot overwrite a newer session.
@MainActor
final class LiveActivityCoordinator: ObservableObject {
    @Published private(set) var lastErrorMessage: String?

    private let logger = Logger(
        subsystem: "com.projectskillbook.app",
        category: "LiveActivity"
    )
    private var synchronizationTail: Task<Void, Never>?

    func synchronize(
        snapshot: ActiveSessionSnapshot?,
        skill: LifeSkill?,
        baseTotalSeconds: Int,
        questAssignment: QuestAssignment? = nil,
        at date: Date = .now
    ) async {
        await enqueue { [weak self] in
            guard let self else { return }
            await self.synchronizeNow(
                snapshot: snapshot,
                skill: skill,
                baseTotalSeconds: baseTotalSeconds,
                questAssignment: questAssignment,
                at: date
            )
        }
    }

    /// Ends only the activity belonging to the committed or discarded session.
    func end(sessionID: UUID) async {
        await enqueue { [weak self] in
            guard let self else { return }
            await self.endMatchingActivity(sessionID: sessionID)
        }
    }

    /// Reconciles every activity when there is no current app session.
    func endAll() async {
        await enqueue { [weak self] in
            guard let self else { return }
            await self.endAllNow()
        }
    }

    private func enqueue(_ operation: @escaping () async -> Void) async {
        let previous = synchronizationTail
        let next = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
        synchronizationTail = next
        await next.value
    }

    private func synchronizeNow(
        snapshot: ActiveSessionSnapshot?,
        skill: LifeSkill?,
        baseTotalSeconds: Int,
        questAssignment: QuestAssignment?,
        at date: Date
    ) async {
        guard let snapshot, let skill, snapshot.skillID == skill.id else {
            await endAllNow()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.notice("Live Activities are disabled for Skilling Time; session remains authoritative.")
            lastErrorMessage = nil
            return
        }

        let state = makeState(
            snapshot: snapshot,
            skill: skill,
            baseTotalSeconds: baseTotalSeconds,
            questAssignment: questAssignment,
            at: date
        )
        let content = ActivityContent(state: state, staleDate: nil)
        let activities = Activity<SkillingTimeActivityAttributes>.activities

        for activity in activities where activity.attributes.sessionID != snapshot.id {
            logger.debug("Ending stale Live Activity for session \(activity.attributes.sessionID.uuidString, privacy: .public).")
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if let existing = activities.first(where: {
            $0.attributes.sessionID == snapshot.id
        }) {
            let attributes = existing.attributes
            let staticIdentityMatches = attributes.skillID == skill.id
                && attributes.skillName == skill.name
                && attributes.symbolName == skill.symbolName
                && attributes.accentHex == skill.accentHex
                && attributes.curveVersion == skill.progressionCurveVersion

            if staticIdentityMatches {
                await existing.update(content)
                logger.debug("Updated Live Activity for session \(snapshot.id.uuidString, privacy: .public).")
                lastErrorMessage = nil
                return
            }

            // Activity attributes are immutable, so identity edits require a fresh activity.
            logger.debug("Replacing Live Activity after immutable session identity changed.")
            await existing.end(nil, dismissalPolicy: .immediate)
        }

        do {
            _ = try Activity.request(
                attributes: SkillingTimeActivityAttributes(
                    sessionID: snapshot.id,
                    skillID: skill.id,
                    skillName: skill.name,
                    symbolName: skill.symbolName,
                    accentHex: skill.accentHex,
                    curveVersion: skill.progressionCurveVersion
                ),
                content: content,
                pushType: nil
            )
            logger.info("Started Live Activity for session \(snapshot.id.uuidString, privacy: .public).")
            lastErrorMessage = nil
        } catch {
            let message = "The Live Activity could not start. \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            lastErrorMessage = message
        }
    }

    private func endMatchingActivity(sessionID: UUID) async {
        for activity in Activity<SkillingTimeActivityAttributes>.activities
            where activity.attributes.sessionID == sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
            logger.info("Ended Live Activity for session \(sessionID.uuidString, privacy: .public).")
        }
        lastErrorMessage = nil
    }

    private func endAllNow() async {
        for activity in Activity<SkillingTimeActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        lastErrorMessage = nil
    }

    private func makeState(
        snapshot: ActiveSessionSnapshot,
        skill: LifeSkill,
        baseTotalSeconds: Int,
        questAssignment: QuestAssignment?,
        at date: Date
    ) -> SkillingTimeActivityAttributes.ContentState {
        let sessionSeconds = snapshot.elapsedSeconds(at: date)
        let startingXP = ProgressionEngine.xp(
            forActiveSeconds: baseTotalSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        let liveXP = ProgressionEngine.xp(
            forActiveSeconds: baseTotalSeconds + sessionSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        let progress = ProgressionEngine.progress(
            forTotalXP: liveXP,
            curveVersion: skill.progressionCurveVersion
        )
        let goal = snapshot.focusGoal.map {
            FocusGoalProgress.evaluate(
                goal: $0,
                sessionSeconds: sessionSeconds,
                liveTotalXP: liveXP
            )
        }
        let quest = QuestEngine.liveStatus(
            assignment: questAssignment,
            snapshot: snapshot,
            skill: skill,
            baseTotalSeconds: baseTotalSeconds,
            at: date
        )

        return SkillingTimeActivityAttributes.ContentState(
            accumulatedActiveSeconds: snapshot.accumulatedActiveSeconds,
            activeSegmentStartedAt: snapshot.activeSegmentStartedAt,
            baseTotalSeconds: baseTotalSeconds,
            level: progress.level,
            rankName: progress.displayRank,
            xpEarned: max(0, liveXP - startingXP),
            xpRemaining: progress.xpRemaining,
            progressFraction: progress.fractionComplete,
            focusGoalTitle: goal?.title,
            focusGoalProgressLabel: goal?.progressLabel,
            focusGoalFraction: goal?.fractionComplete,
            questTitle: quest?.title,
            questProgressLabel: quest?.progressLabel,
            questFraction: quest?.fractionComplete,
            questTimerStart: quest?.timerStart,
            questTimerEnd: quest?.timerEnd,
            questIsComplete: quest?.isComplete,
            isPaused: snapshot.isPaused,
            isAwaitingCommit: snapshot.isAwaitingCommit
        )
    }
}
