import XCTest
@testable import SkillingTime

final class WatchSyncModelTests: XCTestCase {
    func testRunningSessionElapsedTimeUsesTimestampAndAccumulatedDuration() {
        let start = Date(timeIntervalSince1970: 10_000)
        let snapshot = ActiveSessionSnapshot(
            id: UUID(),
            skillID: UUID(),
            startedAt: start,
            accumulatedActiveSeconds: 90,
            activeSegmentStartedAt: start.addingTimeInterval(300),
            finishRequestedAt: nil,
            shouldResumeAfterCancelledFinish: nil,
            focusGoal: nil
        )

        XCTAssertEqual(snapshot.elapsedSeconds(at: start.addingTimeInterval(330)), 120)
    }

    func testWatchEnvelopeRoundTripsTypedState() throws {
        let state = WatchStateSnapshot(
            schemaVersion: SkillingTimeWatchSync.schemaVersion,
            revision: 7,
            generatedAt: Date(timeIntervalSince1970: 10_000),
            skills: [],
            activeSession: nil,
            activeSkill: nil,
            todayActiveSeconds: 1_200,
            streakDays: nil,
            quests: [],
            lastCompletion: nil,
            statusMessage: "Synced"
        )

        let encoded = try WatchPayloadCodec.encode(.state(state))
        let decoded = try XCTUnwrap(WatchPayloadCodec.decode(encoded))

        XCTAssertEqual(decoded.kind, .state)
        XCTAssertEqual(decoded.state, state)
    }

    func testStateStoreRejectsOlderRevisions() {
        let defaults = makeDefaults()
        let store = WatchSyncStateStore(defaults: defaults)
        let newer = makeState(revision: 3)
        let older = makeState(revision: 2)

        XCTAssertTrue(store.saveStateIfNewer(newer))
        XCTAssertFalse(store.saveStateIfNewer(older))
        XCTAssertEqual(store.loadState()?.revision, 3)
    }

    func testInboundCommandIsIdempotentAndHandledOnce() {
        let defaults = makeDefaults()
        let store = WatchSyncStateStore(defaults: defaults)
        let command = WatchSessionCommand.start(skillID: UUID())

        XCTAssertTrue(store.appendInbound(command))
        XCTAssertFalse(store.appendInbound(command))
        let received = store.takeInboundCommands()
        XCTAssertEqual(received.count, 1)
        guard let receivedCommand = received.first else {
            return XCTFail("The queued command was not delivered")
        }
        XCTAssertEqual(receivedCommand.id, command.id)
        XCTAssertEqual(receivedCommand.kind, command.kind)
        XCTAssertEqual(receivedCommand.skillID, command.skillID)
        XCTAssertEqual(
            receivedCommand.createdAt.timeIntervalSince1970,
            command.createdAt.timeIntervalSince1970,
            accuracy: 1
        )

        store.markHandled(command.id)
        XCTAssertFalse(store.appendInbound(command))
        XCTAssertTrue(store.takeInboundCommands().isEmpty)
    }

    func testSessionCommandCarriesStableSessionIdentity() {
        let sessionID = UUID()
        let command = WatchSessionCommand.session(.complete, sessionID: sessionID, expectedRevision: 11)

        XCTAssertEqual(command.kind, .complete)
        XCTAssertEqual(command.sessionID, sessionID)
        XCTAssertEqual(command.expectedRevision, 11)
        XCTAssertNil(command.skillID)
    }

    private func makeState(revision: Int64) -> WatchStateSnapshot {
        WatchStateSnapshot(
            schemaVersion: SkillingTimeWatchSync.schemaVersion,
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: Double(revision)),
            skills: [],
            activeSession: nil,
            activeSkill: nil,
            todayActiveSeconds: nil,
            streakDays: nil,
            quests: [],
            lastCompletion: nil,
            statusMessage: nil
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SkillingTimeTests.watch.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}
