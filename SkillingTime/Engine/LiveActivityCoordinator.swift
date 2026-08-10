import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveActivityCoordinator: ObservableObject {
    @Published private(set) var lastErrorMessage: String?

    func synchronize(
        snapshot: ActiveSessionSnapshot?,
        skill: LifeSkill?,
        baseTotalSeconds: Int,
        at date: Date = .now
    ) async {
        guard let snapshot, let skill, snapshot.skillID == skill.id else {
            await endAll()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastErrorMessage = nil
            return
        }

        let state = makeState(
            snapshot: snapshot,
            skill: skill,
            baseTotalSeconds: baseTotalSeconds,
            at: date
        )
        let content = ActivityContent(state: state, staleDate: nil)
        let activities = Activity<SkillingTimeActivityAttributes>.activities

        for activity in activities where activity.attributes.sessionID != snapshot.id {
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
                lastErrorMessage = nil
                return
            }

            // Activity attributes are immutable, so identity edits require a fresh activity.
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
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "The Live Activity could not start. \(error.localizedDescription)"
        }
    }

    func endAll() async {
        for activity in Activity<SkillingTimeActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        lastErrorMessage = nil
    }

    private func makeState(
        snapshot: ActiveSessionSnapshot,
        skill: LifeSkill,
        baseTotalSeconds: Int,
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
            isPaused: snapshot.isPaused,
            isAwaitingCommit: snapshot.isAwaitingCommit
        )
    }
}
