import Foundation
import SwiftData

enum CharacterPath: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case vigor
    case insight
    case craft
    case expression
    case care
    case stewardship

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vigor: "Vigor"
        case .insight: "Insight"
        case .craft: "Craft"
        case .expression: "Expression"
        case .care: "Care"
        case .stewardship: "Stewardship"
        }
    }

    var description: String {
        switch self {
        case .vigor: "Physical effort, movement, and endurance."
        case .insight: "Study, reflection, and understanding."
        case .craft: "Making, repairing, and practiced technique."
        case .expression: "Creative work and communication."
        case .care: "Supporting people, animals, and community."
        case .stewardship: "Maintaining spaces, routines, and systems."
        }
    }

    var systemImage: String {
        switch self {
        case .vigor: "figure.run"
        case .insight: "book.closed.fill"
        case .craft: "hammer.fill"
        case .expression: "paintpalette.fill"
        case .care: "heart.fill"
        case .stewardship: "house.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .vigor: "C85E5E"
        case .insight: "8A72B5"
        case .craft: "D97A43"
        case .expression: "A96AA2"
        case .care: "C96E91"
        case .stewardship: "55A7A2"
        }
    }
}

extension SkillPathAssignment {
    var path: CharacterPath? { CharacterPath(rawValue: pathRawValue) }
}

enum CharacterTitleSource: String, Codable, Sendable {
    case path
    case expertChallenge
    case legacy
}

extension CharacterTitleUnlock {
    var source: CharacterTitleSource? { CharacterTitleSource(rawValue: sourceRawValue) }
    var path: CharacterPath? { pathRawValue.flatMap(CharacterPath.init(rawValue:)) }
}

enum ExpertChallengeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case activeTime
    case sessionCount
    case focusGoals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeTime: "The Long Work"
        case .sessionCount: "Return to the Work"
        case .focusGoals: "Intent Made Real"
        }
    }

    var systemImage: String {
        switch self {
        case .activeTime: "hourglass"
        case .sessionCount: "repeat.circle.fill"
        case .focusGoals: "scope"
        }
    }

    var targetValue: Int {
        switch self {
        case .activeTime: 10 * 3_600
        case .sessionCount: 20
        case .focusGoals: 8
        }
    }

    func description(skillName: String) -> String {
        switch self {
        case .activeTime:
            "Practice \(skillName) for 10 hours within 30 days."
        case .sessionCount:
            "Complete 20 \(skillName) sessions within 30 days."
        case .focusGoals:
            "Complete 8 \(skillName) Focus Goals within 30 days."
        }
    }
}

extension ExpertChallenge {
    var kind: ExpertChallengeKind? { ExpertChallengeKind(rawValue: kindRawValue) }

    func isActive(at date: Date = .now) -> Bool {
        retiredAt == nil && completedAt == nil && startedAt <= date && date < endsAt
    }

    var isComplete: Bool { completedAt != nil }

    var fractionComplete: Double {
        min(max(Double(currentValue) / Double(max(1, targetValue)), 0), 1)
    }

    var progressLabel: String {
        guard let kind else { return "\(currentValue) of \(targetValue)" }
        switch kind {
        case .activeTime:
            return "\(DurationText.compact(min(currentValue, targetValue))) of \(DurationText.compact(targetValue))"
        case .sessionCount:
            return "\(min(currentValue, targetValue)) of \(targetValue) sessions"
        case .focusGoals:
            return "\(min(currentValue, targetValue)) of \(targetValue) Focus Goals"
        }
    }
}

struct CharacterPathProgressOutcome: Sendable {
    let path: CharacterPath
    let secondsEarned: Int
    let startingProgress: ProgressSnapshot
    let endingProgress: ProgressSnapshot

    var levelsGained: Int {
        max(0, endingProgress.level - startingProgress.level)
    }
}

struct CharacterTitleReveal: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let systemImage: String
}

struct ExpertChallengeReveal: Identifiable, Sendable {
    let id: UUID
    let title: String
    let description: String
    let systemImage: String
}

struct CharacterReconciliationOutcome: Sendable {
    let pathProgress: CharacterPathProgressOutcome?
    let titlesUnlocked: [CharacterTitleReveal]
    let expertChallengesCompleted: [ExpertChallengeReveal]

    static let empty = CharacterReconciliationOutcome(
        pathProgress: nil,
        titlesUnlocked: [],
        expertChallengesCompleted: []
    )
}

struct CharacterTitleDefinition: Identifiable, Sendable {
    let id: String
    let path: CharacterPath
    let requiredLevel: Int
    let title: String
    let description: String

    var systemImage: String { path.systemImage }
}

enum CharacterProgressionEngine {
    static let currentCurveVersion = 1

    static let titleDefinitions: [CharacterTitleDefinition] = CharacterPath.allCases.flatMap {
        path in
        [25, 50, 75, 100].map { level in
            let title = title(for: path, level: level)
            return CharacterTitleDefinition(
                id: "path-title|\(path.rawValue)|\(level)",
                path: path,
                requiredLevel: level,
                title: title,
                description: "Reach Level \(level) on the \(path.title) Path."
            )
        }
    }

    static func progress(
        forActiveSeconds seconds: Int,
        curveVersion: Int = currentCurveVersion
    ) -> ProgressSnapshot {
        let supportedVersion = curveVersion == currentCurveVersion ? curveVersion : currentCurveVersion
        let xp = ProgressionEngine.xp(
            forActiveSeconds: max(0, seconds),
            curveVersion: supportedVersion
        )
        return ProgressionEngine.progress(forTotalXP: xp, curveVersion: supportedVersion)
    }

    static func path(
        for session: SkillSession,
        assignments: [SkillPathAssignment]
    ) -> CharacterPath? {
        let matching = assignments
            .filter { $0.skillID == session.skillID }
            .sorted {
                if $0.effectiveFrom != $1.effectiveFrom {
                    return $0.effectiveFrom < $1.effectiveFrom
                }
                return $0.id < $1.id
            }
        let assignment = matching.last { $0.effectiveFrom <= session.creditedAt }
            ?? matching.first
        return assignment?.path
    }

    static func currentPath(
        for skillID: UUID,
        assignments: [SkillPathAssignment],
        at date: Date = .now
    ) -> CharacterPath? {
        assignments
            .filter { $0.skillID == skillID && $0.effectiveFrom <= date }
            .sorted {
                if $0.effectiveFrom != $1.effectiveFrom {
                    return $0.effectiveFrom > $1.effectiveFrom
                }
                return $0.id > $1.id
            }
            .first?.path
            ?? assignments.first { $0.skillID == skillID }?.path
    }

    static func totals(
        sessions: [SkillSession],
        assignments: [SkillPathAssignment]
    ) -> [CharacterPath: Int] {
        sessions.reduce(into: [:]) { totals, session in
            guard let path = path(for: session, assignments: assignments) else { return }
            totals[path, default: 0] += max(0, session.activeSeconds)
        }
    }

    static func suggestedPath(for skill: LifeSkill) -> CharacterPath {
        let identity = "\(skill.name) \(skill.category)".lowercased()
        let rules: [(CharacterPath, [String])] = [
            (.care, ["family", "child", "parent", "pet", "care", "volunteer", "community"]),
            (.vigor, ["exercise", "run", "walk", "fitness", "strength", "yoga", "sport", "outdoor", "landscap"]),
            (.insight, ["read", "learn", "study", "school", "language", "research", "course", "education"]),
            (.expression, ["creative", "write", "music", "piano", "art", "paint", "photo", "design"]),
            (.craft, ["cook", "repair", "maintenance", "wood", "build", "sew", "bake", "craft"]),
            (.stewardship, ["clean", "laundry", "organ", "home", "garden", "routine", "admin"])
        ]
        return rules.first { _, keywords in
            keywords.contains { identity.contains($0) }
        }?.0 ?? .stewardship
    }

    static func buildSignature(ledgers: [CharacterPathLedger]) -> String {
        let ranked = ledgers.compactMap { ledger -> (CharacterPath, Int)? in
            guard let path = CharacterPath(rawValue: ledger.pathRawValue),
                  ledger.totalActiveSeconds > 0 else { return nil }
            return (path, ledger.totalActiveSeconds)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.rawValue < $1.0.rawValue
        }
        guard let first = ranked.first else { return "Unwritten Path" }
        guard ranked.count > 1 else { return "\(first.0.title) Practitioner" }
        return "\(first.0.title) + \(ranked[1].0.title)"
    }

    private static func title(for path: CharacterPath, level: Int) -> String {
        switch (path, level) {
        case (.vigor, 25): "Wayfarer"
        case (.vigor, 50): "Vanguard"
        case (.vigor, 75): "The Unyielding"
        case (.vigor, 100): "Paragon of Vigor"
        case (.insight, 25): "Scholar"
        case (.insight, 50): "Sage"
        case (.insight, 75): "Luminary"
        case (.insight, 100): "Master of Insight"
        case (.craft, 25): "Artisan"
        case (.craft, 50): "Distinguished Maker"
        case (.craft, 75): "Master Artisan"
        case (.craft, 100): "Paragon of Craft"
        case (.expression, 25): "Creator"
        case (.expression, 50): "Virtuoso"
        case (.expression, 75): "Visionary"
        case (.expression, 100): "Master of Expression"
        case (.care, 25): "Guardian"
        case (.care, 50): "Nurturer"
        case (.care, 75): "Beacon of Care"
        case (.care, 100): "Paragon of Care"
        case (.stewardship, 25): "Steward"
        case (.stewardship, 50): "Keeper"
        case (.stewardship, 75): "Warden of the Work"
        case (.stewardship, 100): "Master Steward"
        default: "\(path.title) Practitioner"
        }
    }
}

@MainActor
enum CharacterProgressionService {
    @discardableResult
    static func prepare(
        in modelContext: ModelContext,
        now: Date = .now
    ) throws -> CharacterReconciliationOutcome {
        do {
            let skills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
            let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
            let outcome = try reconcile(
                skills: skills,
                beforeSessions: sessions,
                afterSessions: sessions,
                triggeringSession: nil,
                in: modelContext,
                now: now
            )
            try modelContext.save()
            return outcome
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func reconcile(
        skills: [LifeSkill],
        beforeSessions: [SkillSession],
        afterSessions: [SkillSession],
        triggeringSession: SkillSession?,
        in modelContext: ModelContext,
        now: Date = .now
    ) throws -> CharacterReconciliationOutcome {
        _ = try ensureProfile(in: modelContext, now: now)
        var assignments = try modelContext.fetch(FetchDescriptor<SkillPathAssignment>())
        ensureAssignments(
            skills: skills,
            sessions: afterSessions,
            assignments: &assignments,
            in: modelContext,
            now: now
        )

        let ledgers = try modelContext.fetch(FetchDescriptor<CharacterPathLedger>())
        rebuildLedgers(
            sessions: afterSessions,
            assignments: assignments,
            existingLedgers: ledgers,
            in: modelContext,
            now: now
        )

        let titleRecords = try modelContext.fetch(FetchDescriptor<CharacterTitleUnlock>())
        let newPathTitles = reconcilePathTitles(
            sessions: afterSessions,
            assignments: assignments,
            existingRecords: titleRecords,
            in: modelContext
        )

        let challenges = try modelContext.fetch(FetchDescriptor<ExpertChallenge>())
        let challengeOutcome = reconcileChallenges(
            challenges: challenges,
            skills: skills,
            sessions: afterSessions,
            existingTitleRecords: titleRecords + newPathTitles.records,
            triggeringSession: triggeringSession,
            in: modelContext,
            now: now
        )

        return CharacterReconciliationOutcome(
            pathProgress: makePathProgress(
                triggeringSession: triggeringSession,
                beforeSessions: beforeSessions,
                afterSessions: afterSessions,
                assignments: assignments
            ),
            titlesUnlocked: newPathTitles.reveals + challengeOutcome.titleReveals,
            expertChallengesCompleted: challengeOutcome.challengeReveals
        )
    }

    static func ensureProfile(
        in modelContext: ModelContext,
        now: Date = .now
    ) throws -> CharacterProfile {
        if let existing = try modelContext.fetch(FetchDescriptor<CharacterProfile>()).first {
            return existing
        }
        let profile = CharacterProfile(createdAt: now)
        modelContext.insert(profile)
        return profile
    }

    static func recordInitialAssignment(
        skill: LifeSkill,
        path: CharacterPath,
        in modelContext: ModelContext,
        confirmed: Bool = true
    ) {
        let assignment = SkillPathAssignment(
            id: SkillPathAssignment.identifier(skillID: skill.id, effectiveFrom: skill.createdAt),
            skillID: skill.id,
            pathRawValue: path.rawValue,
            effectiveFrom: skill.createdAt,
            isConfirmed: confirmed
        )
        modelContext.insert(assignment)
    }

    static func changePath(
        skill: LifeSkill,
        to path: CharacterPath,
        assignments: [SkillPathAssignment],
        in modelContext: ModelContext,
        effectiveFrom: Date = .now
    ) {
        guard CharacterProgressionEngine.currentPath(
            for: skill.id,
            assignments: assignments,
            at: effectiveFrom
        ) != path else { return }

        var date = effectiveFrom
        var id = SkillPathAssignment.identifier(skillID: skill.id, effectiveFrom: date)
        let identifiers = Set(assignments.map(\.id))
        while identifiers.contains(id) {
            date = date.addingTimeInterval(0.001)
            id = SkillPathAssignment.identifier(skillID: skill.id, effectiveFrom: date)
        }
        modelContext.insert(
            SkillPathAssignment(
                id: id,
                skillID: skill.id,
                pathRawValue: path.rawValue,
                effectiveFrom: date,
                isConfirmed: true
            )
        )
    }

    static func confirmInitialPaths(
        selections: [UUID: CharacterPath],
        in modelContext: ModelContext,
        now: Date = .now
    ) throws {
        let profile = try ensureProfile(in: modelContext, now: now)
        let isInitialReview = profile.pathReviewCompletedAt == nil
        let skills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
        let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
        var assignments = try modelContext.fetch(FetchDescriptor<SkillPathAssignment>())
        ensureAssignments(
            skills: skills,
            sessions: sessions,
            assignments: &assignments,
            in: modelContext,
            now: now
        )

        for skill in skills {
            guard let selection = selections[skill.id] else { continue }
            let matching = assignments
                .filter { $0.skillID == skill.id }
                .sorted { $0.effectiveFrom < $1.effectiveFrom }
            if isInitialReview, let first = matching.first {
                first.pathRawValue = selection.rawValue
                first.isConfirmed = true
            } else {
                changePath(
                    skill: skill,
                    to: selection,
                    assignments: assignments,
                    in: modelContext,
                    effectiveFrom: now
                )
            }
        }
        if isInitialReview {
            let quests = try modelContext.fetch(FetchDescriptor<QuestAssignment>())
            for quest in quests
            where quest.templateID == "weekly-character-path"
                && quest.completedAt == nil
                && quest.retiredAt == nil {
                quest.retiredAt = now
            }
        }
        profile.pathReviewCompletedAt = now
        _ = try reconcile(
            skills: skills,
            beforeSessions: sessions,
            afterSessions: sessions,
            triggeringSession: nil,
            in: modelContext,
            now: now
        )
        try modelContext.save()
    }

    @discardableResult
    static func startExpertChallenge(
        skill: LifeSkill,
        kind: ExpertChallengeKind,
        in modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws -> ExpertChallenge {
        let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
        let seconds = SessionAnalytics.totalSeconds(for: skill.id, sessions: sessions)
        let xp = ProgressionEngine.xp(
            forActiveSeconds: seconds,
            curveVersion: skill.progressionCurveVersion
        )
        guard ProgressionEngine.level(
            forTotalXP: xp,
            curveVersion: skill.progressionCurveVersion
        ) >= 75 else {
            throw CharacterProgressionError.expertRankRequired
        }
        let existing = try modelContext.fetch(FetchDescriptor<ExpertChallenge>())
        guard !existing.contains(where: { $0.skillID == skill.id && $0.isActive(at: now) }) else {
            throw CharacterProgressionError.activeChallengeExists
        }
        let end = calendar.date(byAdding: .day, value: 30, to: now)
            ?? now.addingTimeInterval(30 * 86_400)
        let challenge = ExpertChallenge(
            skillID: skill.id,
            kindRawValue: kind.rawValue,
            title: kind.title,
            challengeDescription: kind.description(skillName: skill.name),
            systemImage: kind.systemImage,
            targetValue: kind.targetValue,
            startedAt: now,
            endsAt: end
        )
        modelContext.insert(challenge)
        try modelContext.save()
        return challenge
    }

    static func retireExpertChallenge(
        _ challenge: ExpertChallenge,
        in modelContext: ModelContext,
        now: Date = .now
    ) throws {
        guard challenge.completedAt == nil else { return }
        challenge.retiredAt = now
        try modelContext.save()
    }

    static func saveLegacy(
        skill: LifeSkill,
        masterTitle: String,
        crestSymbolName: String,
        in modelContext: ModelContext,
        now: Date = .now
    ) throws {
        let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
        let seconds = SessionAnalytics.totalSeconds(for: skill.id, sessions: sessions)
        let xp = ProgressionEngine.xp(
            forActiveSeconds: seconds,
            curveVersion: skill.progressionCurveVersion
        )
        guard ProgressionEngine.level(
            forTotalXP: xp,
            curveVersion: skill.progressionCurveVersion
        ) >= 100 else {
            throw CharacterProgressionError.masterRankRequired
        }
        let trimmed = masterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CharacterProgressionError.emptyTitle }

        let legacies = try modelContext.fetch(FetchDescriptor<SkillLegacy>())
        if let existing = legacies.first(where: { $0.skillID == skill.id }) {
            existing.masterTitle = trimmed
            existing.crestSymbolName = crestSymbolName
            existing.chosenAt = now
        } else {
            modelContext.insert(
                SkillLegacy(
                    skillID: skill.id,
                    masterTitle: trimmed,
                    crestSymbolName: crestSymbolName,
                    chosenAt: now
                )
            )
        }

        let identifier = "legacy|\(skill.id.uuidString.lowercased())"
        let titles = try modelContext.fetch(FetchDescriptor<CharacterTitleUnlock>())
        if let existingTitle = titles.first(where: { $0.id == identifier }) {
            existingTitle.title = trimmed
            existingTitle.titleDescription = "A Legacy title earned through mastery of \(skill.name)."
            existingTitle.systemImage = crestSymbolName
        } else {
            modelContext.insert(
                CharacterTitleUnlock(
                    id: identifier,
                    title: trimmed,
                    titleDescription: "A Legacy title earned through mastery of \(skill.name).",
                    systemImage: crestSymbolName,
                    sourceRawValue: CharacterTitleSource.legacy.rawValue,
                    skillID: skill.id,
                    unlockedAt: now
                )
            )
        }
        try modelContext.save()
    }

    private static func ensureAssignments(
        skills: [LifeSkill],
        sessions: [SkillSession],
        assignments: inout [SkillPathAssignment],
        in modelContext: ModelContext,
        now: Date
    ) {
        for skill in skills where !assignments.contains(where: { $0.skillID == skill.id }) {
            let earliestSession = sessions
                .filter { $0.skillID == skill.id }
                .map(\.creditedAt)
                .min()
            let effectiveFrom = min(skill.createdAt, earliestSession ?? skill.createdAt)
            let assignment = SkillPathAssignment(
                id: SkillPathAssignment.identifier(
                    skillID: skill.id,
                    effectiveFrom: effectiveFrom
                ),
                skillID: skill.id,
                pathRawValue: CharacterProgressionEngine.suggestedPath(for: skill).rawValue,
                effectiveFrom: effectiveFrom,
                createdAt: now,
                isConfirmed: false
            )
            modelContext.insert(assignment)
            assignments.append(assignment)
        }
    }

    private static func rebuildLedgers(
        sessions: [SkillSession],
        assignments: [SkillPathAssignment],
        existingLedgers: [CharacterPathLedger],
        in modelContext: ModelContext,
        now: Date
    ) {
        var aggregates: [CharacterPath: (seconds: Int, count: Int, latest: Date?)] = [:]
        for session in sessions {
            guard let path = CharacterProgressionEngine.path(
                for: session,
                assignments: assignments
            ) else { continue }
            var aggregate = aggregates[path] ?? (0, 0, nil)
            aggregate.seconds += max(0, session.activeSeconds)
            aggregate.count += 1
            aggregate.latest = max(aggregate.latest ?? .distantPast, session.creditedAt)
            aggregates[path] = aggregate
        }

        for path in CharacterPath.allCases {
            let aggregate = aggregates[path] ?? (0, 0, nil)
            if let ledger = existingLedgers.first(where: { $0.pathRawValue == path.rawValue }) {
                ledger.totalActiveSeconds = aggregate.seconds
                ledger.sessionCount = aggregate.count
                ledger.latestSessionAt = aggregate.latest
                ledger.curveVersion = CharacterProgressionEngine.currentCurveVersion
                ledger.rebuiltAt = now
            } else {
                modelContext.insert(
                    CharacterPathLedger(
                        pathRawValue: path.rawValue,
                        totalActiveSeconds: aggregate.seconds,
                        sessionCount: aggregate.count,
                        latestSessionAt: aggregate.latest,
                        curveVersion: CharacterProgressionEngine.currentCurveVersion,
                        rebuiltAt: now
                    )
                )
            }
        }
    }

    private static func reconcilePathTitles(
        sessions: [SkillSession],
        assignments: [SkillPathAssignment],
        existingRecords: [CharacterTitleUnlock],
        in modelContext: ModelContext
    ) -> (records: [CharacterTitleUnlock], reveals: [CharacterTitleReveal]) {
        var known = Set(existingRecords.map(\.id))
        var secondsByPath: [CharacterPath: Int] = [:]
        var inserted: [CharacterTitleUnlock] = []
        var reveals: [CharacterTitleReveal] = []

        for session in sessions.sorted(by: sessionOrder) {
            guard let path = CharacterProgressionEngine.path(
                for: session,
                assignments: assignments
            ) else { continue }
            secondsByPath[path, default: 0] += max(0, session.activeSeconds)
            let level = CharacterProgressionEngine.progress(
                forActiveSeconds: secondsByPath[path, default: 0]
            ).level
            for definition in CharacterProgressionEngine.titleDefinitions
            where definition.path == path && definition.requiredLevel <= level
                && !known.contains(definition.id) {
                let record = CharacterTitleUnlock(
                    id: definition.id,
                    title: definition.title,
                    titleDescription: definition.description,
                    systemImage: definition.systemImage,
                    sourceRawValue: CharacterTitleSource.path.rawValue,
                    pathRawValue: path.rawValue,
                    unlockedAt: session.creditedAt,
                    triggeringSessionID: session.id
                )
                modelContext.insert(record)
                inserted.append(record)
                known.insert(definition.id)
                reveals.append(
                    CharacterTitleReveal(
                        id: definition.id,
                        title: definition.title,
                        description: definition.description,
                        systemImage: definition.systemImage
                    )
                )
            }
        }
        return (inserted, reveals)
    }

    private static func reconcileChallenges(
        challenges: [ExpertChallenge],
        skills: [LifeSkill],
        sessions: [SkillSession],
        existingTitleRecords: [CharacterTitleUnlock],
        triggeringSession: SkillSession?,
        in modelContext: ModelContext,
        now: Date
    ) -> (challengeReveals: [ExpertChallengeReveal], titleReveals: [CharacterTitleReveal]) {
        let skillsByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        var knownTitleIDs = Set(existingTitleRecords.map(\.id))
        var challengeReveals: [ExpertChallengeReveal] = []
        var titleReveals: [CharacterTitleReveal] = []

        for challenge in challenges where challenge.retiredAt == nil {
            let previousValue = challenge.currentValue
            let matching = sessions.filter {
                $0.skillID == challenge.skillID
                    && challenge.startedAt <= $0.creditedAt
                    && $0.creditedAt < challenge.endsAt
            }
            let value: Int
            switch challenge.kind {
            case .activeTime:
                value = matching.reduce(0) { $0 + max(0, $1.activeSeconds) }
            case .sessionCount:
                value = matching.count
            case .focusGoals:
                value = matching.filter(\.completedFocusGoal).count
            case nil:
                value = 0
            }
            challenge.currentValue = max(0, value)

            guard challenge.completedAt == nil, value >= challenge.targetValue else { continue }
            let completingSession: SkillSession?
            if let triggeringSession,
               triggeringSession.skillID == challenge.skillID,
               challenge.startedAt <= triggeringSession.creditedAt,
               triggeringSession.creditedAt < challenge.endsAt,
               previousValue < challenge.targetValue {
                completingSession = triggeringSession
            } else {
                completingSession = matching.max(by: sessionOrder)
            }
            challenge.completedAt = completingSession?.creditedAt ?? now
            challenge.triggeringSessionID = completingSession?.id

            challengeReveals.append(
                ExpertChallengeReveal(
                    id: challenge.id,
                    title: challenge.title,
                    description: challenge.challengeDescription,
                    systemImage: challenge.systemImage
                )
            )

            guard let skill = skillsByID[challenge.skillID] else { continue }
            let titleID = "expert|\(challenge.id.uuidString.lowercased())"
            guard !knownTitleIDs.contains(titleID) else { continue }
            let title = "Expert of \(skill.name)"
            let description = "Complete an Expert Challenge in \(skill.name)."
            modelContext.insert(
                CharacterTitleUnlock(
                    id: titleID,
                    title: title,
                    titleDescription: description,
                    systemImage: "checkmark.seal.fill",
                    sourceRawValue: CharacterTitleSource.expertChallenge.rawValue,
                    skillID: skill.id,
                    unlockedAt: challenge.completedAt ?? now,
                    triggeringSessionID: completingSession?.id
                )
            )
            knownTitleIDs.insert(titleID)
            titleReveals.append(
                CharacterTitleReveal(
                    id: titleID,
                    title: title,
                    description: description,
                    systemImage: "checkmark.seal.fill"
                )
            )
        }
        return (challengeReveals, titleReveals)
    }

    private static func makePathProgress(
        triggeringSession: SkillSession?,
        beforeSessions: [SkillSession],
        afterSessions: [SkillSession],
        assignments: [SkillPathAssignment]
    ) -> CharacterPathProgressOutcome? {
        guard let triggeringSession,
              let path = CharacterProgressionEngine.path(
                for: triggeringSession,
                assignments: assignments
              ) else { return nil }
        let before = CharacterProgressionEngine.totals(
            sessions: beforeSessions,
            assignments: assignments
        )[path, default: 0]
        let after = CharacterProgressionEngine.totals(
            sessions: afterSessions,
            assignments: assignments
        )[path, default: 0]
        return CharacterPathProgressOutcome(
            path: path,
            secondsEarned: max(0, after - before),
            startingProgress: CharacterProgressionEngine.progress(forActiveSeconds: before),
            endingProgress: CharacterProgressionEngine.progress(forActiveSeconds: after)
        )
    }

    private static func sessionOrder(_ lhs: SkillSession, _ rhs: SkillSession) -> Bool {
        if lhs.creditedAt != rhs.creditedAt { return lhs.creditedAt < rhs.creditedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum CharacterProgressionError: LocalizedError {
    case expertRankRequired
    case masterRankRequired
    case activeChallengeExists
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .expertRankRequired: "Reach Level 75 in this Skill first."
        case .masterRankRequired: "Reach Level 100 in this Skill first."
        case .activeChallengeExists: "This Skill already has an active Expert Challenge."
        case .emptyTitle: "Enter a Master title."
        }
    }
}
