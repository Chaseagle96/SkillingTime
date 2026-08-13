import Combine
import Foundation
import OSLog
@preconcurrency import WatchConnectivity

enum SkillingTimeWatchConnectionState: String, Sendable {
    case unsupported
    case activating
    case connected
    case phoneUnavailable
    case inactive
}

/// The only object that talks to WatchConnectivity. Domain code sends typed
/// commands and publishes replaceable snapshots without knowing about
/// WCSession dictionaries, reachability, or queued delivery.
@MainActor
final class SkillingTimeWatchConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var receivedState: WatchStateSnapshot?
    @Published private(set) var connectionState: SkillingTimeWatchConnectionState = .inactive
    @Published private(set) var incomingCommandVersion = 0
    @Published private(set) var lastCommandMessage: String?
    @Published private(set) var lastErrorMessage: String?

    private let session: WCSession
    private let store: WatchSyncStateStore
    private let logger = Logger(subsystem: "com.projectskillbook.app", category: "WatchConnectivity")
    private var pendingStatusMessage: String?
    private var lastCompletion: WatchCompletionSnapshot?

    init(
        session: WCSession = .default,
        defaults: UserDefaults = SkillingTimeSharedConfiguration.makeSharedDefaults()
    ) {
        self.session = session
        self.store = WatchSyncStateStore(defaults: defaults)
        self.receivedState = store.loadState()
        super.init()
        session.delegate = self
    }

    func activate() {
        guard WCSession.isSupported() else {
            connectionState = .unsupported
            return
        }

        connectionState = .activating
        session.activate()
    }

    /// Publishes semantic state changes only. Elapsed time is rendered from
    /// the session timestamps on each device, so this is never called per tick.
    func publish(_ state: WatchStateSnapshot) {
        let revision = store.nextRevision()
        let publishedState = state.with(
            revision: revision,
            statusMessage: pendingStatusMessage,
            lastCompletion: lastCompletion
        )

        guard store.saveStateIfNewer(publishedState) else {
            logger.error("Could not persist Watch state revision \(revision)")
            return
        }
        receivedState = publishedState

        do {
            try session.updateApplicationContext(
                WatchPayloadCodec.encode(.state(publishedState))
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Watch state could not be queued: \(error.localizedDescription)"
            logger.error("Application context update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sends a user action interactively when possible and queues it as durable
    /// user info when the iPhone is not reachable. The command remains typed
    /// and idempotent at the receiving domain boundary.
    func send(_ command: WatchSessionCommand) {
        guard let payload = try? WatchPayloadCodec.encode(.command(command)) else {
            lastCommandMessage = "This action could not be encoded."
            return
        }

        if session.activationState != .activated {
            session.activate()
        }

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: { [weak self] reply in
                    guard let result = WatchPayloadCodec.decode(reply)?.result else { return }
                    Task { @MainActor [weak self] in
                        self?.receive(result: result)
                    }
                },
                errorHandler: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.queue(
                            payload,
                            commandID: command.id,
                            message: "Queued until the iPhone is reachable."
                        )
                        self?.logger.error(
                            "Interactive Watch command failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            )
            lastCommandMessage = "Sent to iPhone."
        } else {
            queue(payload, commandID: command.id, message: "Queued until the iPhone is reachable.")
        }
    }

    func setLastCompletion(_ completion: WatchCompletionSnapshot?) {
        lastCompletion = completion
    }

    func clearError() {
        lastErrorMessage = nil
    }

    /// Returns durable commands exactly once. A command UUID is marked handled
    /// before domain execution, while SessionCommitService remains idempotent
    /// for a repeated completion received from an older queued delivery.
    func takeIncomingCommands() -> [WatchSessionCommand] {
        let commands = store.takeInboundCommands()
        commands.forEach { store.markHandled($0.id) }
        return commands
    }

    func recordCommandResult(_ result: WatchCommandResult) {
        pendingStatusMessage = result.message
        lastCommandMessage = result.message
        if !result.accepted {
            lastErrorMessage = result.message
        }
    }

    private func queue(_ payload: [String: Any], commandID: UUID, message: String) {
        session.transferUserInfo(payload)
        lastCommandMessage = message
        pendingStatusMessage = message
        logger.info("Queued Watch command \(commandID.uuidString, privacy: .public)")
    }

    private func receive(state: WatchStateSnapshot) {
        guard state.schemaVersion == SkillingTimeWatchSync.schemaVersion else {
            logger.error("Rejected unsupported Watch state schema \(state.schemaVersion)")
            return
        }
        guard store.saveStateIfNewer(state) else {
            logger.debug("Ignored stale Watch state revision \(state.revision)")
            return
        }
        receivedState = state
        pendingStatusMessage = state.statusMessage
        lastCompletion = state.lastCompletion
        lastErrorMessage = nil
    }

    private func receive(command: WatchSessionCommand) {
        guard store.appendInbound(command) else {
            logger.debug("Ignored duplicate Watch command \(command.id.uuidString, privacy: .public)")
            return
        }
        incomingCommandVersion += 1
    }

    private func receive(result: WatchCommandResult) {
        recordCommandResult(result)
    }

    private func receive(envelope: SkillingTimeWatchEnvelope) {
        switch envelope.kind {
        case .state:
            if let state = envelope.state { receive(state: state) }
        case .command:
            if let command = envelope.command { receive(command: command) }
        case .result:
            if let result = envelope.result { receive(result: result) }
        }
    }

    @objc nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let errorMessage = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let errorMessage {
                connectionState = .inactive
                lastErrorMessage = "WatchConnectivity activation failed: \(errorMessage)"
                logger.error("Activation failed: \(errorMessage, privacy: .public)")
            } else if activationState == .activated {
                connectionState = session.isReachable ? .connected : .phoneUnavailable
                if let state = WatchPayloadCodec.decode(session.receivedApplicationContext)?.state {
                    receive(state: state)
                }
            } else {
                connectionState = .inactive
            }
        }
    }

#if os(iOS)
    // These lifecycle callbacks are part of the iOS WCSessionDelegate surface.
    // watchOS marks them unavailable because a Watch session is not deactivated
    // and reactivated in the same way as its iPhone counterpart.
    @objc nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.connectionState = .inactive
        }
    }

    @objc nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.connectionState = .inactive
            self?.session.activate()
        }
    }
#endif

    @objc nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self, connectionState != .unsupported else { return }
            connectionState = session.isReachable ? .connected : .phoneUnavailable
        }
    }

    @objc nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let envelope = WatchPayloadCodec.decode(applicationContext) else { return }
        Task { @MainActor [weak self] in
            self?.receive(envelope: envelope)
        }
    }

    @objc nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        guard let envelope = WatchPayloadCodec.decode(userInfo) else { return }
        Task { @MainActor [weak self] in
            self?.receive(envelope: envelope)
        }
    }

    @objc nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let envelope = WatchPayloadCodec.decode(message) else { return }
        Task { @MainActor [weak self] in
            self?.receive(envelope: envelope)
        }
    }

    @objc nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let envelope = WatchPayloadCodec.decode(message) else {
            replyHandler([:])
            return
        }

        if let command = envelope.command {
            let acknowledgement = WatchCommandResult(
                commandID: command.id,
                accepted: true,
                message: "Command received by Skilling Time.",
                stateRevision: nil
            )
            replyHandler((try? WatchPayloadCodec.encode(.result(acknowledgement))) ?? [:])
        } else {
            replyHandler([:])
        }

        Task { @MainActor [weak self] in
            self?.receive(envelope: envelope)
        }
    }
}
