import Combine
import Foundation
import UserNotifications

struct ProgressionNotificationPlan: Equatable, Sendable {
    let identifier: String
    let fireAfterSeconds: Int
    let title: String
    let body: String
    let targetTotalXP: Int
}

enum ProgressionNotificationPlanner {
    static let notificationIdentifier = SkillingTimeSharedConfiguration.progressionNotificationIdentifier

    static func plan(
        snapshot: ActiveSessionSnapshot,
        skill: LifeSkill,
        baseTotalSeconds: Int,
        at date: Date = .now
    ) -> ProgressionNotificationPlan? {
        guard !snapshot.isPaused, !snapshot.isAwaitingCommit else { return nil }

        let currentTotalSeconds = baseTotalSeconds + snapshot.elapsedSeconds(at: date)
        let currentXP = ProgressionEngine.xp(
            forActiveSeconds: currentTotalSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        let progress = ProgressionEngine.progress(
            forTotalXP: currentXP,
            curveVersion: skill.progressionCurveVersion
        )
        let targetXP = ProgressionEngine.nextThresholdXP(
            after: progress,
            curveVersion: skill.progressionCurveVersion
        )
        let targetSeconds = targetXP * ProgressionEngine.secondsPerXP(
            curveVersion: skill.progressionCurveVersion
        )
        let remainingSeconds = max(1, targetSeconds - currentTotalSeconds)
        let destination = progress.level < ProgressionEngine.maximumLevel(
            curveVersion: skill.progressionCurveVersion
        )
            ? "Level \(progress.level + 1)"
            : "Mastery star \(progress.masteryStars + 1)"

        return ProgressionNotificationPlan(
            identifier: notificationIdentifier,
            fireAfterSeconds: remainingSeconds,
            title: "\(skill.name) increased",
            body: "Your active session reached \(destination). Return to keep progressing.",
            targetTotalXP: targetXP
        )
    }
}

@MainActor
final class ProgressionNotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var alertsEnabled: Bool
    @Published private(set) var lastErrorMessage: String?

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = SkillingTimeSharedConfiguration.makeSharedDefaults()
    ) {
        self.center = center
        self.defaults = defaults
        alertsEnabled = defaults.bool(
            forKey: SkillingTimeSharedConfiguration.notificationPreferenceKey
        )
    }

    var canSchedule: Bool {
        alertsEnabled && [
            UNAuthorizationStatus.authorized,
            .provisional,
            .ephemeral
        ].contains(authorizationStatus)
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if authorizationStatus == .denied {
            alertsEnabled = false
            defaults.set(false, forKey: SkillingTimeSharedConfiguration.notificationPreferenceKey)
            cancelPendingThreshold()
        }
    }

    func enableAlerts() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorizationStatus()
            let statusAllowsAlerts = [
                UNAuthorizationStatus.authorized,
                .provisional,
                .ephemeral
            ].contains(authorizationStatus)
            alertsEnabled = granted || statusAllowsAlerts
            defaults.set(
                alertsEnabled,
                forKey: SkillingTimeSharedConfiguration.notificationPreferenceKey
            )
            lastErrorMessage = alertsEnabled
                ? nil
                : "Progression alerts were not authorized."
        } catch {
            alertsEnabled = false
            lastErrorMessage = error.localizedDescription
        }
    }

    func disableAlerts() {
        alertsEnabled = false
        defaults.set(false, forKey: SkillingTimeSharedConfiguration.notificationPreferenceKey)
        cancelPendingThreshold()
    }

    func synchronize(
        snapshot: ActiveSessionSnapshot?,
        skill: LifeSkill?,
        baseTotalSeconds: Int,
        at date: Date = .now
    ) async {
        await refreshAuthorizationStatus()
        guard canSchedule,
              let snapshot,
              let skill,
              snapshot.skillID == skill.id,
              let plan = ProgressionNotificationPlanner.plan(
                snapshot: snapshot,
                skill: skill,
                baseTotalSeconds: baseTotalSeconds,
                at: date
              ) else {
            cancelPendingThreshold()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.threadIdentifier = "skillingtime-progression"
        content.userInfo = [
            "skillID": skill.id.uuidString,
            "sessionID": snapshot.id.uuidString,
            "targetTotalXP": plan.targetTotalXP
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(plan.fireAfterSeconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: plan.identifier,
            content: content,
            trigger: trigger
        )

        do {
            center.removePendingNotificationRequests(withIdentifiers: [plan.identifier])
            try await center.add(request)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "The next progression alert could not be scheduled. \(error.localizedDescription)"
        }
    }

    func cancelPendingThreshold() {
        center.removePendingNotificationRequests(
            withIdentifiers: [ProgressionNotificationPlanner.notificationIdentifier]
        )
    }
}
