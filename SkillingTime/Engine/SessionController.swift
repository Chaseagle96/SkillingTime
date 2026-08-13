import Combine
import Foundation

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

@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var activeSession: ActiveSessionSnapshot?
    @Published private(set) var storageErrorMessage: String?

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?
    private var defaultsObserver: AnyCancellable?

    convenience init() {
        self.init(
            defaults: SkillingTimeSharedConfiguration.makeSharedDefaults(),
            legacyDefaults: .standard
        )
    }

    init(defaults: UserDefaults, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        restore()
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshFromSharedStorage()
                }
            }
    }

    @discardableResult
    func start(
        skillID: UUID,
        focusGoal: SessionFocusGoal? = nil,
        at date: Date = .now
    ) -> Bool {
        guard activeSession == nil else { return false }

        activeSession = ActiveSessionSnapshot(
            id: UUID(),
            skillID: skillID,
            startedAt: date,
            accumulatedActiveSeconds: 0,
            activeSegmentStartedAt: date,
            finishRequestedAt: nil,
            shouldResumeAfterCancelledFinish: nil,
            focusGoal: focusGoal
        )
        persist()
        return storageErrorMessage == nil
    }

    func pause(at date: Date = .now) {
        guard var session = activeSession, !session.isPaused, !session.isAwaitingCommit else { return }
        session.accumulatedActiveSeconds = session.elapsedSeconds(at: date)
        session.activeSegmentStartedAt = nil
        activeSession = session
        persist()
    }

    func resume(at date: Date = .now) {
        guard var session = activeSession, session.isPaused, !session.isAwaitingCommit else { return }
        session.activeSegmentStartedAt = date
        activeSession = session
        persist()
    }

    /// Freezes the authoritative finish instant without deleting the recoverable timer.
    /// Repeated calls return the same pending draft so saving is safely retryable.
    func requestFinish(at date: Date = .now) -> CompletedSessionDraft? {
        guard var session = activeSession else { return nil }

        if let requestedAt = session.finishRequestedAt {
            return makeDraft(
                from: session,
                endedAt: requestedAt,
                shouldResumeOnCancel: session.shouldResumeAfterCancelledFinish ?? false
            )
        }

        let wasRunning = !session.isPaused
        if wasRunning {
            session.accumulatedActiveSeconds = session.elapsedSeconds(at: date)
            session.activeSegmentStartedAt = nil
        }
        session.finishRequestedAt = date
        session.shouldResumeAfterCancelledFinish = wasRunning
        activeSession = session
        persist()

        return makeDraft(
            from: session,
            endedAt: date,
            shouldResumeOnCancel: wasRunning
        )
    }

    func cancelFinish(shouldResume: Bool, at date: Date = .now) {
        guard var session = activeSession, session.isAwaitingCommit else { return }
        let resumeAfterCancel = session.shouldResumeAfterCancelledFinish ?? shouldResume
        session.finishRequestedAt = nil
        session.shouldResumeAfterCancelledFinish = nil
        if resumeAfterCancel {
            session.activeSegmentStartedAt = date
        }
        activeSession = session
        persist()
    }

    /// Removes the pending timer only after SwiftData has durably committed its session UUID.
    func markCommitted(sessionID: UUID) {
        guard activeSession?.id == sessionID else { return }
        clear()
    }

    func discard() {
        clear()
    }

    /// Pulls in pause or resume actions performed by the Live Activity intent.
    func refreshFromSharedStorage() {
        guard let data = defaults.data(
            forKey: SkillingTimeSharedConfiguration.activeSessionKey
        ) else {
            if activeSession != nil {
                activeSession = nil
            }
            return
        }

        do {
            let restored = try JSONDecoder().decode(ActiveSessionSnapshot.self, from: data)
            if restored != activeSession {
                activeSession = restored
            }
            storageErrorMessage = nil
        } catch {
            storageErrorMessage = "The shared active timer could not be refreshed."
        }
    }

    private func makeDraft(
        from session: ActiveSessionSnapshot,
        endedAt: Date,
        shouldResumeOnCancel: Bool
    ) -> CompletedSessionDraft {
        CompletedSessionDraft(
            id: session.id,
            skillID: session.skillID,
            startedAt: session.startedAt,
            endedAt: endedAt,
            activeSeconds: session.elapsedSeconds(at: endedAt),
            focusGoal: session.focusGoal,
            shouldResumeOnCancel: shouldResumeOnCancel
        )
    }

    private func restore() {
        let currentKey = SkillingTimeSharedConfiguration.activeSessionKey
        let legacyKey = SkillingTimeSharedConfiguration.legacyActiveSessionKey
        let sharedData = defaults.data(forKey: currentKey) ?? defaults.data(forKey: legacyKey)
        let fallbackData = legacyDefaults?.data(forKey: currentKey)
            ?? legacyDefaults?.data(forKey: legacyKey)
        let storedData = sharedData ?? fallbackData
        guard let storedData else {
            activeSession = nil
            return
        }

        do {
            activeSession = try JSONDecoder().decode(ActiveSessionSnapshot.self, from: storedData)
            storageErrorMessage = nil
            if defaults.data(forKey: currentKey) == nil {
                persist()
                defaults.removeObject(forKey: legacyKey)
                legacyDefaults?.removeObject(forKey: currentKey)
                legacyDefaults?.removeObject(forKey: legacyKey)
            }
        } catch {
            activeSession = nil
            storageErrorMessage = "The previous active timer could not be restored."
            defaults.removeObject(forKey: currentKey)
            defaults.removeObject(forKey: legacyKey)
        }
    }

    private func persist() {
        guard let session = activeSession else { return }

        do {
            let data = try JSONEncoder().encode(session)
            defaults.set(data, forKey: SkillingTimeSharedConfiguration.activeSessionKey)
            storageErrorMessage = nil
        } catch {
            storageErrorMessage = "The active timer could not be saved."
        }
    }

    private func clear() {
        activeSession = nil
        storageErrorMessage = nil
        defaults.removeObject(forKey: SkillingTimeSharedConfiguration.activeSessionKey)
        defaults.removeObject(forKey: SkillingTimeSharedConfiguration.legacyActiveSessionKey)
        legacyDefaults?.removeObject(forKey: SkillingTimeSharedConfiguration.activeSessionKey)
        legacyDefaults?.removeObject(forKey: SkillingTimeSharedConfiguration.legacyActiveSessionKey)
    }
}
