import Combine
import Foundation

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

@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var activeSession: ActiveSessionSnapshot?
    @Published private(set) var storageErrorMessage: String?
    /// Incremented when a view needs the Live Activity and progression alert
    /// refreshed (for example after a level-up). RootTabView performs the sync
    /// so every refresh includes the current quest and runs in order.
    @Published private(set) var ambientSyncRequest = 0

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?
    private var defaultsObserver: AnyCancellable?

    convenience init() {
        let shared = SkillingTimeSharedConfiguration.makeSharedDefaults()
        self.init(
            defaults: shared,
            // Without a working App Group the shared store *is* .standard; treating it
            // as a separate legacy store would delete the key restore just wrote.
            legacyDefaults: shared === UserDefaults.standard ? nil : .standard
        )
    }

    init(defaults: UserDefaults, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        restore()
        // No object filter: the Live Activity intent writes through its own
        // UserDefaults instance, and filtering by instance would never match it.
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
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

        let session = ActiveSessionSnapshot(
            id: UUID(),
            skillID: skillID,
            startedAt: date,
            accumulatedActiveSeconds: 0,
            activeSegmentStartedAt: date,
            finishRequestedAt: nil,
            shouldResumeAfterCancelledFinish: nil,
            focusGoal: focusGoal
        )
        activeSession = session
        persist()
        guard storageErrorMessage == nil else {
            // Never leave a timer running that could not be made recoverable.
            activeSession = nil
            return false
        }
        return true
    }

    func requestAmbientSync() {
        ambientSyncRequest &+= 1
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
            storageErrorMessage = "The previous active timer could not be restored. Its data was kept aside."
            // Keep the raw bytes so a later version (or support) can recover them.
            defaults.set(storedData, forKey: SkillingTimeSharedConfiguration.unreadableActiveSessionKey)
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
