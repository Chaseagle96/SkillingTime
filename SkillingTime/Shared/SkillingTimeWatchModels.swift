import Foundation

enum SkillingTimeWatchSync {
    static let schemaVersion = 1
    static let stateKey = "skillbook.watch.state.v1"
    static let inboundCommandsKey = "skillbook.watch.inbound-commands.v1"
    static let handledCommandIDsKey = "skillbook.watch.handled-command-ids.v1"
    static let revisionKey = "skillbook.watch.revision.v1"
    static let maxHandledCommandIDs = 100
}

struct WatchSkillSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let symbolName: String
    let accentHex: String
    let level: Int
    let rankName: String
    let totalXP: Int
    let xpIntoLevel: Int
    let xpForNextLevel: Int
    let progressFraction: Double
    let totalActiveSeconds: Int
    let sessionCount: Int
    let sortOrder: Int
}

struct WatchQuestSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let cadenceTitle: String
    let progressLabel: String
    let fractionComplete: Double
    let isComplete: Bool
}

struct WatchCompletionSnapshot: Codable, Equatable, Sendable {
    let sessionID: UUID
    let skillID: UUID
    let skillName: String
    let durationSeconds: Int
    let xpEarned: Int
    let endingLevel: Int
    let endingRankName: String
    let completedAt: Date
}

/// Replaceable, versioned state delivered to the Watch through application
/// context. The Watch never needs to mirror the iPhone's SwiftData store.
struct WatchStateSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var revision: Int64
    let generatedAt: Date
    let skills: [WatchSkillSnapshot]
    let activeSession: ActiveSessionSnapshot?
    let activeSkill: WatchSkillSnapshot?
    let todayActiveSeconds: Int?
    let streakDays: Int?
    let quests: [WatchQuestSnapshot]
    let lastCompletion: WatchCompletionSnapshot?
    var statusMessage: String?

    func with(
        revision: Int64? = nil,
        statusMessage: String? = nil,
        lastCompletion: WatchCompletionSnapshot? = nil
    ) -> WatchStateSnapshot {
        WatchStateSnapshot(
            schemaVersion: schemaVersion,
            revision: revision ?? self.revision,
            generatedAt: .now,
            skills: skills,
            activeSession: activeSession,
            activeSkill: activeSkill,
            todayActiveSeconds: todayActiveSeconds,
            streakDays: streakDays,
            quests: quests,
            lastCompletion: lastCompletion,
            statusMessage: statusMessage
        )
    }
}

enum WatchCommandKind: String, Codable, Sendable {
    case start
    case pause
    case resume
    case complete
    case cancel
    case refresh
}

struct WatchSessionCommand: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: WatchCommandKind
    let skillID: UUID?
    let sessionID: UUID?
    let createdAt: Date
    let expectedRevision: Int64?

    init(
        id: UUID = UUID(),
        kind: WatchCommandKind,
        skillID: UUID? = nil,
        sessionID: UUID? = nil,
        createdAt: Date = .now,
        expectedRevision: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.skillID = skillID
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.expectedRevision = expectedRevision
    }

    static func start(skillID: UUID, expectedRevision: Int64? = nil) -> WatchSessionCommand {
        WatchSessionCommand(
            kind: .start,
            skillID: skillID,
            expectedRevision: expectedRevision
        )
    }

    static func session(
        _ kind: WatchCommandKind,
        sessionID: UUID,
        expectedRevision: Int64? = nil
    ) -> WatchSessionCommand {
        WatchSessionCommand(
            kind: kind,
            sessionID: sessionID,
            expectedRevision: expectedRevision
        )
    }

    static func refresh(expectedRevision: Int64? = nil) -> WatchSessionCommand {
        WatchSessionCommand(kind: .refresh, expectedRevision: expectedRevision)
    }
}

struct WatchCommandResult: Codable, Equatable, Sendable {
    let commandID: UUID
    let accepted: Bool
    let message: String
    let stateRevision: Int64?
}

enum WatchEnvelopeKind: String, Codable, Sendable {
    case state
    case command
    case result
}

struct SkillingTimeWatchEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let kind: WatchEnvelopeKind
    let state: WatchStateSnapshot?
    let command: WatchSessionCommand?
    let result: WatchCommandResult?

    static func state(_ state: WatchStateSnapshot) -> SkillingTimeWatchEnvelope {
        SkillingTimeWatchEnvelope(
            schemaVersion: SkillingTimeWatchSync.schemaVersion,
            kind: .state,
            state: state,
            command: nil,
            result: nil
        )
    }

    static func command(_ command: WatchSessionCommand) -> SkillingTimeWatchEnvelope {
        SkillingTimeWatchEnvelope(
            schemaVersion: SkillingTimeWatchSync.schemaVersion,
            kind: .command,
            state: nil,
            command: command,
            result: nil
        )
    }

    static func result(_ result: WatchCommandResult) -> SkillingTimeWatchEnvelope {
        SkillingTimeWatchEnvelope(
            schemaVersion: SkillingTimeWatchSync.schemaVersion,
            kind: .result,
            state: nil,
            command: nil,
            result: result
        )
    }
}

enum WatchPayloadCodec {
    private static let payloadKey = "skillingTimePayload"

    static func encode(_ envelope: SkillingTimeWatchEnvelope) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        return [
            "schemaVersion": envelope.schemaVersion,
            payloadKey: data
        ]
    }

    static func decode(_ payload: [String: Any]) -> SkillingTimeWatchEnvelope? {
        guard let data = payload[payloadKey] as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(SkillingTimeWatchEnvelope.self, from: data),
              envelope.schemaVersion == SkillingTimeWatchSync.schemaVersion else {
            return nil
        }
        return envelope
    }
}

/// Small App Group store used for replaceable Watch state and durable inbound
/// commands. It deliberately stores snapshots, not a second copy of SwiftData.
struct WatchSyncStateStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = SkillingTimeSharedConfiguration.makeSharedDefaults()) {
        self.defaults = defaults
    }

    func loadState() -> WatchStateSnapshot? {
        guard let data = defaults.data(forKey: SkillingTimeWatchSync.stateKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchStateSnapshot.self, from: data)
    }

    @discardableResult
    func saveStateIfNewer(_ state: WatchStateSnapshot) -> Bool {
        if let current = loadState(), state.revision < current.revision {
            return false
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return false }
        defaults.set(data, forKey: SkillingTimeWatchSync.stateKey)
        return true
    }

    func nextRevision() -> Int64 {
        let next = Int64(defaults.integer(forKey: SkillingTimeWatchSync.revisionKey)) + 1
        defaults.set(Int(next), forKey: SkillingTimeWatchSync.revisionKey)
        return next
    }

    @discardableResult
    func appendInbound(_ command: WatchSessionCommand) -> Bool {
        guard !isHandled(command.id) else { return false }
        var commands = loadCommands()
        guard !commands.contains(where: { $0.id == command.id }) else { return false }
        commands.append(command)
        saveCommands(commands)
        return true
    }

    func takeInboundCommands() -> [WatchSessionCommand] {
        let commands = loadCommands()
        return commands.filter { !isHandled($0.id) }
    }

    func markHandled(_ id: UUID) {
        var ids = handledIDs()
        ids.removeAll { $0 == id }
        ids.append(id)
        if ids.count > SkillingTimeWatchSync.maxHandledCommandIDs {
            ids.removeFirst(ids.count - SkillingTimeWatchSync.maxHandledCommandIDs)
        }
        defaults.set(ids.map(\.uuidString), forKey: SkillingTimeWatchSync.handledCommandIDsKey)

        var remaining = loadCommands()
        remaining.removeAll { $0.id == id }
        if remaining.isEmpty {
            defaults.removeObject(forKey: SkillingTimeWatchSync.inboundCommandsKey)
        } else {
            saveCommands(remaining)
        }
    }

    private func isHandled(_ id: UUID) -> Bool {
        handledIDs().contains(id)
    }

    private func handledIDs() -> [UUID] {
        (defaults.stringArray(forKey: SkillingTimeWatchSync.handledCommandIDsKey) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    private func loadCommands() -> [WatchSessionCommand] {
        guard let data = defaults.data(forKey: SkillingTimeWatchSync.inboundCommandsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WatchSessionCommand].self, from: data)) ?? []
    }

    private func saveCommands(_ commands: [WatchSessionCommand]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(commands) else { return }
        defaults.set(data, forKey: SkillingTimeWatchSync.inboundCommandsKey)
    }
}
