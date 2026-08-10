import Foundation
import SwiftData

struct ResolvedAchievementReward: Hashable, Sendable {
    let id: String
    let achievementID: String
    let skillID: UUID?
    let unlockedAt: Date
    let triggeringSessionID: UUID?
}

struct ResolvedChronicleReward: Hashable, Sendable {
    let id: String
    let skillID: UUID
    let milestoneLevel: Int
    let unlockedAt: Date
    let triggeringSessionID: UUID
}

struct RewardResolution: Sendable {
    let achievements: [ResolvedAchievementReward]
    let chronicles: [ResolvedChronicleReward]

    var allIdentifiers: Set<String> {
        Set(achievements.map(\.id) + chronicles.map(\.id))
    }
}

enum RewardResolver {
    static func resolve(
        skills: [LifeSkill],
        sessions: [SkillSession],
        calendar: Calendar = .current
    ) -> RewardResolution {
        let skillsByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        let sessionsBySkill = Dictionary(grouping: sessions, by: \.skillID)
        var achievements: [ResolvedAchievementReward] = []
        var chronicles: [ResolvedChronicleReward] = []

        for skill in skills {
            let matching = (sessionsBySkill[skill.id] ?? []).sorted(by: sessionOrder)
            var state = SkillRewardState()
            var unresolvedAchievements = Dictionary(
                uniqueKeysWithValues: AchievementEngine.skillDefinitions.map { ($0.id, $0) }
            )
            var unresolvedMilestones = Set(ChronicleContent.entries.map(\.level))

            for session in matching {
                state.apply(session: session, calendar: calendar)
                let xp = ProgressionEngine.xp(
                    forActiveSeconds: state.totalSeconds,
                    curveVersion: skill.progressionCurveVersion
                )
                let level = ProgressionEngine.level(
                    forTotalXP: xp,
                    curveVersion: skill.progressionCurveVersion
                )

                let earnedDefinitions = unresolvedAchievements.values.filter {
                    state.satisfies($0.criterion, level: level)
                }
                for definition in earnedDefinitions {
                    achievements.append(
                        ResolvedAchievementReward(
                            id: AchievementUnlock.identifier(
                                achievementID: definition.id,
                                skillID: skill.id
                            ),
                            achievementID: definition.id,
                            skillID: skill.id,
                            unlockedAt: session.creditedAt,
                            triggeringSessionID: session.id
                        )
                    )
                    unresolvedAchievements.removeValue(forKey: definition.id)
                }

                let earnedMilestones = unresolvedMilestones.filter { level >= $0 }
                for milestone in earnedMilestones {
                    chronicles.append(
                        ResolvedChronicleReward(
                            id: ChronicleUnlock.identifier(
                                skillID: skill.id,
                                milestoneLevel: milestone
                            ),
                            skillID: skill.id,
                            milestoneLevel: milestone,
                            unlockedAt: session.creditedAt,
                            triggeringSessionID: session.id
                        )
                    )
                    unresolvedMilestones.remove(milestone)
                }
            }
        }

        achievements.append(
            contentsOf: resolveGlobalAchievements(
                skills: skills,
                skillsByID: skillsByID,
                sessions: sessions
            )
        )

        return RewardResolution(
            achievements: achievements.sorted(by: rewardOrder),
            chronicles: chronicles.sorted(by: chronicleOrder)
        )
    }

    private static func resolveGlobalAchievements(
        skills: [LifeSkill],
        skillsByID: [UUID: LifeSkill],
        sessions: [SkillSession]
    ) -> [ResolvedAchievementReward] {
        var earliestCreditBySkill: [UUID: Date] = [:]
        for session in sessions {
            if let existing = earliestCreditBySkill[session.skillID] {
                if session.creditedAt < existing {
                    earliestCreditBySkill[session.skillID] = session.creditedAt
                }
            } else {
                earliestCreditBySkill[session.skillID] = session.creditedAt
            }
        }

        var events: [GlobalRewardEvent] = skills.map { skill in
            let activationDate = min(skill.createdAt, earliestCreditBySkill[skill.id] ?? skill.createdAt)
            return .skill(skill, activationDate)
        }
        events.append(contentsOf: sessions.map(GlobalRewardEvent.session))
        events.sort(by: globalEventOrder)

        var unresolved = Dictionary(
            uniqueKeysWithValues: AchievementEngine.globalDefinitions.map { ($0.id, $0) }
        )
        var createdSkillIDs = Set<UUID>()
        var secondsBySkill: [UUID: Int] = [:]
        var levelsBySkill: [UUID: Int] = [:]
        var totalLevel = 0
        var totalSeconds = 0
        var activeSkillIDs = Set<UUID>()
        var results: [ResolvedAchievementReward] = []

        for event in events {
            let eventDate: Date
            let triggeringSessionID: UUID?

            switch event {
            case .skill(let skill, let date):
                eventDate = date
                triggeringSessionID = nil
                if createdSkillIDs.insert(skill.id).inserted {
                    levelsBySkill[skill.id] = 1
                    totalLevel += 1
                }

            case .session(let session):
                eventDate = session.creditedAt
                triggeringSessionID = session.id
                totalSeconds += max(0, session.activeSeconds)
                if session.activeSeconds > 0 {
                    activeSkillIDs.insert(session.skillID)
                }

                guard let skill = skillsByID[session.skillID] else { continue }
                if createdSkillIDs.insert(skill.id).inserted {
                    levelsBySkill[skill.id] = 1
                    totalLevel += 1
                }

                let oldLevel = levelsBySkill[skill.id] ?? 1
                secondsBySkill[skill.id, default: 0] += max(0, session.activeSeconds)
                let newXP = ProgressionEngine.xp(
                    forActiveSeconds: secondsBySkill[skill.id, default: 0],
                    curveVersion: skill.progressionCurveVersion
                )
                let newLevel = ProgressionEngine.level(
                    forTotalXP: newXP,
                    curveVersion: skill.progressionCurveVersion
                )
                levelsBySkill[skill.id] = newLevel
                totalLevel += newLevel - oldLevel
            }

            let earnedDefinitions = unresolved.values.filter {
                globalCriterion(
                    $0.criterion,
                    totalLevel: totalLevel,
                    activeSkillCount: activeSkillIDs.count,
                    totalSeconds: totalSeconds
                )
            }
            for definition in earnedDefinitions {
                results.append(
                    ResolvedAchievementReward(
                        id: AchievementUnlock.identifier(
                            achievementID: definition.id,
                            skillID: nil
                        ),
                        achievementID: definition.id,
                        skillID: nil,
                        unlockedAt: eventDate,
                        triggeringSessionID: triggeringSessionID
                    )
                )
                unresolved.removeValue(forKey: definition.id)
            }
        }

        return results
    }

    private static func globalCriterion(
        _ criterion: AchievementCriterion,
        totalLevel: Int,
        activeSkillCount: Int,
        totalSeconds: Int
    ) -> Bool {
        switch criterion {
        case .totalLevel(let target):
            totalLevel >= target
        case .activeSkillCount(let target):
            activeSkillCount >= target
        case .globalDuration(let target):
            totalSeconds >= target
        default:
            false
        }
    }

    private static func sessionOrder(_ lhs: SkillSession, _ rhs: SkillSession) -> Bool {
        if lhs.creditedAt != rhs.creditedAt {
            return lhs.creditedAt < rhs.creditedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func rewardOrder(_ lhs: ResolvedAchievementReward, _ rhs: ResolvedAchievementReward) -> Bool {
        if lhs.unlockedAt != rhs.unlockedAt {
            return lhs.unlockedAt < rhs.unlockedAt
        }
        return lhs.id < rhs.id
    }

    private static func chronicleOrder(_ lhs: ResolvedChronicleReward, _ rhs: ResolvedChronicleReward) -> Bool {
        if lhs.unlockedAt != rhs.unlockedAt {
            return lhs.unlockedAt < rhs.unlockedAt
        }
        return lhs.id < rhs.id
    }

    private static func globalEventOrder(_ lhs: GlobalRewardEvent, _ rhs: GlobalRewardEvent) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.identifier < rhs.identifier
    }
}

private struct SkillRewardState {
    var totalSeconds = 0
    var sessionCount = 0
    var longestSession = 0
    var activeDays = Set<Date>()
    var activeWeeks = Set<String>()
    var activeMonths = Set<String>()
    var maximumReturnGapDays = 0
    var previousEndedAt: Date?

    mutating func apply(session: SkillSession, calendar: Calendar) {
        totalSeconds += max(0, session.activeSeconds)
        sessionCount += 1
        longestSession = max(longestSession, session.activeSeconds)
        activeDays.insert(calendar.startOfDay(for: session.creditedAt))

        let week = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: session.creditedAt
        )
        activeWeeks.insert("\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)")

        let month = calendar.dateComponents([.year, .month], from: session.creditedAt)
        activeMonths.insert("\(month.year ?? 0)-\(month.month ?? 0)")

        if let previousEndedAt {
            let gap = calendar.dateComponents(
                [.day],
                from: previousEndedAt,
                to: session.startedAt
            ).day ?? 0
            maximumReturnGapDays = max(maximumReturnGapDays, gap)
        }
        previousEndedAt = max(previousEndedAt ?? session.endedAt, session.endedAt)
    }

    func satisfies(_ criterion: AchievementCriterion, level: Int) -> Bool {
        switch criterion {
        case .skillLevel(let target):
            level >= target
        case .skillDuration(let target):
            totalSeconds >= target
        case .skillSessionCount(let target):
            sessionCount >= target
        case .longestSession(let target):
            longestSession >= target
        case .activeDays(let target):
            activeDays.count >= target
        case .returnAfterDays(let target):
            maximumReturnGapDays >= target
        case .activeWeeks(let target):
            activeWeeks.count >= target
        case .activeMonths(let target):
            activeMonths.count >= target
        default:
            false
        }
    }
}

private enum GlobalRewardEvent {
    case skill(LifeSkill, Date)
    case session(SkillSession)

    var date: Date {
        switch self {
        case .skill(_, let date): date
        case .session(let session): session.creditedAt
        }
    }

    var priority: Int {
        switch self {
        case .skill: 0
        case .session: 1
        }
    }

    var identifier: String {
        switch self {
        case .skill(let skill, _): skill.id.uuidString
        case .session(let session): session.id.uuidString
        }
    }
}

@MainActor
enum RewardRecordReconciler {
    @discardableResult
    static func reconcile(
        resolution: RewardResolution,
        achievementRecords: [AchievementUnlock],
        chronicleRecords: [ChronicleUnlock],
        in modelContext: ModelContext
    ) -> Bool {
        var changed = false
        let achievementByID = Dictionary(uniqueKeysWithValues: achievementRecords.map { ($0.id, $0) })

        for resolved in resolution.achievements {
            if achievementByID[resolved.id] == nil {
                modelContext.insert(
                    AchievementUnlock(
                        id: resolved.id,
                        achievementID: resolved.achievementID,
                        skillID: resolved.skillID,
                        unlockedAt: resolved.unlockedAt,
                        triggeringSessionID: resolved.triggeringSessionID
                    )
                )
                changed = true
            }
        }

        let chronicleByID = Dictionary(uniqueKeysWithValues: chronicleRecords.map { ($0.id, $0) })

        for resolved in resolution.chronicles {
            if chronicleByID[resolved.id] == nil {
                modelContext.insert(
                    ChronicleUnlock(
                        id: resolved.id,
                        skillID: resolved.skillID,
                        milestoneLevel: resolved.milestoneLevel,
                        unlockedAt: resolved.unlockedAt,
                        triggeringSessionID: resolved.triggeringSessionID
                    )
                )
                changed = true
            }
        }

        return changed
    }
}

@MainActor
enum RewardBackfillService {
    static func reconcileAll(in modelContext: ModelContext) throws {
        let skills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
        let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
        let achievements = try modelContext.fetch(FetchDescriptor<AchievementUnlock>())
        let chronicles = try modelContext.fetch(FetchDescriptor<ChronicleUnlock>())
        let resolution = RewardResolver.resolve(skills: skills, sessions: sessions)

        guard RewardRecordReconciler.reconcile(
            resolution: resolution,
            achievementRecords: achievements,
            chronicleRecords: chronicles,
            in: modelContext
        ) else { return }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
