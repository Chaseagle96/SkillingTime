import Foundation
import SwiftData

enum QuestCadence: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

enum QuestKind: String, Codable, Sendable {
    case activeTime
    case sameSkillSessions
    case distinctSkills
    case gainLevels
    case deepSession
    case oldFriend
    case journeymanXP
    case focusGoal
    case sessionCount
}

extension QuestAssignment {
    var cadence: QuestCadence? { QuestCadence(rawValue: cadenceRawValue) }
    var kind: QuestKind? { QuestKind(rawValue: kindRawValue) }
    var isRetired: Bool { retiredAt != nil }
}

struct QuestStatus: Identifiable, Equatable, Sendable {
    let id: String
    let assignmentID: String
    let cadence: QuestCadence
    let kind: QuestKind
    let title: String
    let description: String
    let systemImage: String
    let currentValue: Int
    let targetValue: Int
    let progressLabel: String
    let periodStart: Date
    let periodEnd: Date
    let targetSkillID: UUID?
    let completedAt: Date?

    var isComplete: Bool { completedAt != nil || currentValue >= targetValue }
    var fractionComplete: Double {
        guard targetValue > 0 else { return 1 }
        return min(max(Double(currentValue) / Double(targetValue), 0), 1)
    }
}

private struct QuestCandidate {
    let templateID: String
    let cadence: QuestCadence
    let kind: QuestKind
    let title: String
    let description: String
    let systemImage: String
    let targetSkillID: UUID?
    let targetSkillName: String?
    let targetValue: Int
}

enum QuestEngine {
    static let generationVersion = 1
    static let dailyAssignmentCount = 3
    static let weeklyAssignmentCount = 2

    static func currentStatuses(
        assignments: [QuestAssignment],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [QuestStatus] {
        assignments
            .filter { isCurrent($0, calendar: calendar, now: now) }
            .sorted {
                if $0.cadenceRawValue != $1.cadenceRawValue {
                    return ($0.cadence == .daily ? 0 : 1) < ($1.cadence == .daily ? 0 : 1)
                }
                return $0.slot < $1.slot
            }
            .compactMap(status)
    }

    static func status(_ assignment: QuestAssignment) -> QuestStatus? {
        guard let cadence = assignment.cadence, let kind = assignment.kind else { return nil }
        return QuestStatus(
            id: assignment.id,
            assignmentID: assignment.id,
            cadence: cadence,
            kind: kind,
            title: assignment.title,
            description: assignment.questDescription,
            systemImage: assignment.systemImage,
            currentValue: max(0, assignment.currentValue),
            targetValue: max(1, assignment.targetValue),
            progressLabel: progressLabel(
                kind: kind,
                current: assignment.currentValue,
                target: assignment.targetValue
            ),
            periodStart: assignment.periodStart,
            periodEnd: assignment.periodEnd,
            targetSkillID: assignment.targetSkillID,
            completedAt: assignment.completedAt
        )
    }

    static func isCurrent(
        _ assignment: QuestAssignment,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Bool {
        !assignment.isRetired
            && assignment.periodStart <= now
            && now < assignment.periodEnd
            && assignment.cadence != nil
    }

    static func period(
        for cadence: QuestCadence,
        calendar: Calendar = .current,
        containing date: Date = .now
    ) -> DateInterval {
        switch cadence {
        case .daily:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)
                ?? start.addingTimeInterval(86_400)
            return DateInterval(start: start, end: end)
        case .weekly:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
                return interval
            }
            let start = calendar.startOfDay(for: date)
            return DateInterval(
                start: start,
                end: start.addingTimeInterval(7 * 86_400)
            )
        }
    }

    static func makeAssignments(
        cadence: QuestCadence,
        skills: [LifeSkill],
        sessions: [SkillSession],
        existingAssignments: [QuestAssignment],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [QuestAssignment] {
        let interval = period(for: cadence, calendar: calendar, containing: now)
        let activeSkills = skills.filter { !$0.isArchived }
        let candidates = generationCandidates(
            cadence: cadence,
            activeSkills: activeSkills,
            sessions: sessions,
            interval: interval,
            calendar: calendar
        )
        guard !candidates.isEmpty else { return [] }

        let desiredCount = cadence == .daily
            ? dailyAssignmentCount
            : weeklyAssignmentCount
        let activeInPeriod = existingAssignments.filter {
            !$0.isRetired
                && $0.cadence == cadence
                && sameInstant($0.periodStart, interval.start)
        }
        let occupiedSlots = Set(activeInPeriod.map(\.slot))
        let usedTemplateIDs = Set(activeInPeriod.map(\.templateID))
        let openSlots = (0..<desiredCount).filter { !occupiedSlots.contains($0) }
        guard !openSlots.isEmpty else { return [] }

        let anchorID = cadence == .daily ? "daily-put-in-time" : "weekly-long-haul"
        let recentCutoff = cadence == .daily
            ? interval.start.addingTimeInterval(-3 * 86_400)
            : interval.start.addingTimeInterval(-21 * 86_400)
        let recentlyUsed = Set(
            existingAssignments
                .filter { $0.periodStart >= recentCutoff }
                .map(\.templateID)
        )
        let seed = "\(cadence.rawValue)|\(Int(interval.start.timeIntervalSince1970))|\(activeSkills.map { $0.id.uuidString }.sorted().joined(separator: ","))"
        var available = candidates.filter { !usedTemplateIDs.contains($0.templateID) }
        available.sort {
            if ($0.templateID == anchorID) != ($1.templateID == anchorID) {
                return $0.templateID == anchorID
            }
            if recentlyUsed.contains($0.templateID) != recentlyUsed.contains($1.templateID) {
                return !recentlyUsed.contains($0.templateID)
            }
            let lhsHash = stableHash("\(seed)|\($0.templateID)|\($0.targetSkillID?.uuidString ?? "global")")
            let rhsHash = stableHash("\(seed)|\($1.templateID)|\($1.targetSkillID?.uuidString ?? "global")")
            if lhsHash != rhsHash { return lhsHash < rhsHash }
            return $0.templateID < $1.templateID
        }

        return zip(openSlots, available.prefix(openSlots.count)).map { pair in
            let (slot, candidate) = pair
            return makeAssignment(
                candidate: candidate,
                slot: slot,
                interval: interval,
                calendar: calendar,
                now: now
            )
        }
    }

    static func currentValue(
        for assignment: QuestAssignment,
        skills: [LifeSkill],
        sessions: [SkillSession]
    ) -> Int {
        guard let kind = assignment.kind else { return 0 }
        let periodSessions = sessions.filter {
            assignment.periodStart <= $0.creditedAt && $0.creditedAt < assignment.periodEnd
        }
        let matchingSkillSessions: [SkillSession]
        if let targetSkillID = assignment.targetSkillID {
            matchingSkillSessions = periodSessions.filter { $0.skillID == targetSkillID }
        } else {
            matchingSkillSessions = periodSessions
        }

        switch kind {
        case .activeTime:
            return matchingSkillSessions.reduce(0) { $0 + max(0, $1.activeSeconds) }
        case .sameSkillSessions, .oldFriend:
            return matchingSkillSessions.count
        case .distinctSkills:
            return Set(periodSessions.map(\.skillID)).count
        case .gainLevels:
            return levelsGained(
                between: assignment.periodStart,
                and: assignment.periodEnd,
                skills: skills,
                sessions: sessions
            )
        case .deepSession:
            return matchingSkillSessions.map(\.activeSeconds).max() ?? 0
        case .journeymanXP:
            guard let targetSkillID = assignment.targetSkillID,
                  let skill = skills.first(where: { $0.id == targetSkillID }) else { return 0 }
            return xpGained(
                for: skill,
                between: assignment.periodStart,
                and: assignment.periodEnd,
                sessions: sessions
            )
        case .focusGoal:
            return matchingSkillSessions.filter(\.completedFocusGoal).count
        case .sessionCount:
            return periodSessions.count
        }
    }

    static func liveStatus(
        assignment: QuestAssignment?,
        snapshot: ActiveSessionSnapshot,
        skill: LifeSkill,
        baseTotalSeconds: Int,
        at date: Date = .now
    ) -> QuestLiveStatus? {
        guard let assignment,
              !assignment.isRetired,
              assignment.completedAt == nil,
              let kind = assignment.kind,
              let status = status(assignment),
              assignment.targetSkillID == nil || assignment.targetSkillID == skill.id
        else { return nil }

        let sessionSeconds = snapshot.elapsedSeconds(at: date)
        let current: Int
        let target: Int
        let isTimeBased: Bool
        let liveProgressLabel: String?
        switch kind {
        case .activeTime:
            current = assignment.currentValue + sessionSeconds
            target = max(1, assignment.targetValue)
            isTimeBased = true
            liveProgressLabel = nil
        case .deepSession:
            current = max(assignment.currentValue, sessionSeconds)
            target = max(1, assignment.targetValue)
            isTimeBased = true
            liveProgressLabel = nil
        case .journeymanXP:
            let startingXP = ProgressionEngine.xp(
                forActiveSeconds: baseTotalSeconds,
                curveVersion: skill.progressionCurveVersion
            )
            let liveXP = ProgressionEngine.xp(
                forActiveSeconds: baseTotalSeconds + sessionSeconds,
                curveVersion: skill.progressionCurveVersion
            )
            current = assignment.currentValue + max(0, liveXP - startingXP)
            target = max(1, assignment.targetValue)
            isTimeBased = false
            liveProgressLabel = nil
        case .focusGoal:
            guard let focusGoal = snapshot.focusGoal else { return nil }
            let liveXP = ProgressionEngine.xp(
                forActiveSeconds: baseTotalSeconds + sessionSeconds,
                curveVersion: skill.progressionCurveVersion
            )
            let goal = FocusGoalProgress.evaluate(
                goal: focusGoal,
                sessionSeconds: sessionSeconds,
                liveTotalXP: liveXP
            )
            current = goal.currentValue
            target = max(1, goal.targetValue)
            isTimeBased = focusGoal.kind == .duration
            liveProgressLabel = goal.progressLabel
        default:
            return nil
        }

        let fraction = min(max(Double(current) / Double(target), 0), 1)
        let virtualTimerStart: Date?
        let timerEnd: Date?
        if isTimeBased,
           !snapshot.isPaused,
           let segmentStartedAt = snapshot.activeSegmentStartedAt,
           current < target {
            virtualTimerStart = segmentStartedAt.addingTimeInterval(TimeInterval(-current))
            timerEnd = virtualTimerStart?.addingTimeInterval(TimeInterval(target))
        } else {
            virtualTimerStart = nil
            timerEnd = nil
        }

        return QuestLiveStatus(
            title: status.title,
            progressLabel: liveProgressLabel
                ?? progressLabel(kind: kind, current: current, target: target),
            fractionComplete: fraction,
            timerStart: virtualTimerStart,
            timerEnd: timerEnd,
            isComplete: current >= target
        )
    }

    private static func generationCandidates(
        cadence: QuestCadence,
        activeSkills: [LifeSkill],
        sessions: [SkillSession],
        interval: DateInterval,
        calendar: Calendar
    ) -> [QuestCandidate] {
        switch cadence {
        case .daily:
            return dailyCandidates(
                activeSkills: activeSkills,
                sessions: sessions,
                interval: interval,
                calendar: calendar
            )
        case .weekly:
            return weeklyCandidates(
                activeSkills: activeSkills,
                sessions: sessions,
                interval: interval,
                calendar: calendar
            )
        }
    }

    private static func dailyCandidates(
        activeSkills: [LifeSkill],
        sessions: [SkillSession],
        interval: DateInterval,
        calendar: Calendar
    ) -> [QuestCandidate] {
        guard !activeSkills.isEmpty else { return [] }
        let dailyTarget = adaptiveDailySeconds(
            sessions: sessions,
            before: interval.start,
            calendar: calendar
        )
        let deepTarget = adaptiveDeepSessionSeconds(sessions: sessions, before: interval.start)
        var candidates: [QuestCandidate] = [
            QuestCandidate(
                templateID: "daily-put-in-time",
                cadence: .daily,
                kind: .activeTime,
                title: "Put in the Time",
                description: "Skill for \(DurationText.compact(dailyTarget)) today.",
                systemImage: "hourglass",
                targetSkillID: nil,
                targetSkillName: nil,
                targetValue: dailyTarget
            ),
            QuestCandidate(
                templateID: "daily-deep-session",
                cadence: .daily,
                kind: .deepSession,
                title: "Deep Session",
                description: "Complete one \(DurationText.compact(deepTarget)) session.",
                systemImage: "timer",
                targetSkillID: nil,
                targetSkillName: nil,
                targetValue: deepTarget
            )
        ]

        if activeSkills.count >= 3 {
            candidates.append(
                QuestCandidate(
                    templateID: "daily-diversify",
                    cadence: .daily,
                    kind: .distinctSkills,
                    title: "Diversify",
                    description: "Train three different Skills today.",
                    systemImage: "arrow.triangle.branch",
                    targetSkillID: nil,
                    targetSkillName: nil,
                    targetValue: 3
                )
            )
        }

        if let skill = preferredSkill(from: activeSkills, sessions: sessions) {
            candidates.append(
                QuestCandidate(
                    templateID: "daily-double-down",
                    cadence: .daily,
                    kind: .sameSkillSessions,
                    title: "Double Down",
                    description: "Complete two \(skill.name) sessions today.",
                    systemImage: "repeat.circle.fill",
                    targetSkillID: skill.id,
                    targetSkillName: skill.name,
                    targetValue: 2
                )
            )
        }

        let canGainLevel = activeSkills.contains { skill in
            progress(for: skill, sessions: sessions).level
                < ProgressionEngine.maximumLevel(curveVersion: skill.progressionCurveVersion)
        }
        if canGainLevel {
            candidates.append(
                QuestCandidate(
                    templateID: "daily-level-best",
                    cadence: .daily,
                    kind: .gainLevels,
                    title: "Level Best",
                    description: "Gain a level in any Skill today.",
                    systemImage: "chevron.up.2",
                    targetSkillID: nil,
                    targetSkillName: nil,
                    targetValue: 1
                )
            )
        }

        if let oldFriend = oldFriendSkill(
            from: activeSkills,
            sessions: sessions,
            before: interval.start,
            calendar: calendar
        ) {
            candidates.append(
                QuestCandidate(
                    templateID: "daily-old-friend",
                    cadence: .daily,
                    kind: .oldFriend,
                    title: "Old Friend",
                    description: "Return to \(oldFriend.name) after time away.",
                    systemImage: "clock.arrow.circlepath",
                    targetSkillID: oldFriend.id,
                    targetSkillName: oldFriend.name,
                    targetValue: 1
                )
            )
        }

        let focusSkills = activeSkills.filter {
            progress(for: $0, sessions: sessions).level >= 25
        }
        if let focusSkill = preferredSkill(from: focusSkills, sessions: sessions) {
            candidates.append(
                QuestCandidate(
                    templateID: "daily-finish-focus",
                    cadence: .daily,
                    kind: .focusGoal,
                    title: "Finish What You Started",
                    description: "Complete a Focus Goal in \(focusSkill.name).",
                    systemImage: "scope",
                    targetSkillID: focusSkill.id,
                    targetSkillName: focusSkill.name,
                    targetValue: 1
                )
            )
        }

        return candidates
    }

    private static func weeklyCandidates(
        activeSkills: [LifeSkill],
        sessions: [SkillSession],
        interval: DateInterval,
        calendar: Calendar
    ) -> [QuestCandidate] {
        guard !activeSkills.isEmpty else { return [] }
        let weeklyTarget = adaptiveWeeklySeconds(
            sessions: sessions,
            before: interval.start,
            calendar: calendar
        )
        let sessionTarget = adaptiveWeeklySessionCount(
            sessions: sessions,
            before: interval.start
        )
        var candidates: [QuestCandidate] = [
            QuestCandidate(
                templateID: "weekly-long-haul",
                cadence: .weekly,
                kind: .activeTime,
                title: "The Long Haul",
                description: "Accumulate \(DurationText.compact(weeklyTarget)) of Skilling Time this week.",
                systemImage: "calendar.badge.clock",
                targetSkillID: nil,
                targetSkillName: nil,
                targetValue: weeklyTarget
            ),
            QuestCandidate(
                templateID: "weekly-return-often",
                cadence: .weekly,
                kind: .sessionCount,
                title: "Return Often",
                description: "Complete \(sessionTarget) sessions this week.",
                systemImage: "repeat.circle.fill",
                targetSkillID: nil,
                targetSkillName: nil,
                targetValue: sessionTarget
            )
        ]

        if activeSkills.count >= 3 {
            let target = min(4, activeSkills.count)
            candidates.append(
                QuestCandidate(
                    templateID: "weekly-many-paths",
                    cadence: .weekly,
                    kind: .distinctSkills,
                    title: "Walk Several Paths",
                    description: "Practice \(target) different Skills this week.",
                    systemImage: "map.fill",
                    targetSkillID: nil,
                    targetSkillName: nil,
                    targetValue: target
                )
            )
        }

        let journeymanSkills = activeSkills.filter {
            progress(for: $0, sessions: sessions).level >= 50
        }
        if let skill = preferredSkill(from: journeymanSkills, sessions: sessions) {
            candidates.append(
                QuestCandidate(
                    templateID: "weekly-journeyman-work",
                    cadence: .weekly,
                    kind: .journeymanXP,
                    title: "Journeyman's Work",
                    description: "Earn 2,000 XP in \(skill.name) this week.",
                    systemImage: "shield.fill",
                    targetSkillID: skill.id,
                    targetSkillName: skill.name,
                    targetValue: 2_000
                )
            )
        }

        let deepTarget = min(
            90 * 60,
            max(45 * 60, adaptiveDeepSessionSeconds(sessions: sessions, before: interval.start))
        )
        candidates.append(
            QuestCandidate(
                templateID: "weekly-deep-practice",
                cadence: .weekly,
                kind: .deepSession,
                title: "Deep Practice",
                description: "Complete one \(DurationText.compact(deepTarget)) session this week.",
                systemImage: "brain.head.profile",
                targetSkillID: nil,
                targetSkillName: nil,
                targetValue: deepTarget
            )
        )

        return candidates
    }

    private static func makeAssignment(
        candidate: QuestCandidate,
        slot: Int,
        interval: DateInterval,
        calendar: Calendar,
        now: Date
    ) -> QuestAssignment {
        let skillScope = candidate.targetSkillID?.uuidString.lowercased() ?? "global"
        let id = [
            "quest-v\(generationVersion)",
            candidate.cadence.rawValue,
            String(Int(interval.start.timeIntervalSince1970)),
            String(slot),
            candidate.templateID,
            skillScope
        ].joined(separator: "|")
        return QuestAssignment(
            id: id,
            templateID: candidate.templateID,
            cadenceRawValue: candidate.cadence.rawValue,
            kindRawValue: candidate.kind.rawValue,
            slot: slot,
            periodStart: interval.start,
            periodEnd: interval.end,
            timeZoneIdentifier: calendar.timeZone.identifier,
            title: candidate.title,
            questDescription: candidate.description,
            systemImage: candidate.systemImage,
            targetSkillID: candidate.targetSkillID,
            targetSkillName: candidate.targetSkillName,
            targetValue: candidate.targetValue,
            generatedAt: now,
            generationVersion: generationVersion
        )
    }

    private static func progressLabel(kind: QuestKind, current: Int, target: Int) -> String {
        let safeCurrent = max(0, current)
        let safeTarget = max(1, target)
        switch kind {
        case .activeTime, .deepSession:
            return "\(DurationText.compact(min(safeCurrent, safeTarget))) of \(DurationText.compact(safeTarget))"
        case .journeymanXP:
            return "\(min(safeCurrent, safeTarget).formatted()) of \(safeTarget.formatted()) XP"
        case .distinctSkills:
            return "\(min(safeCurrent, safeTarget)) of \(safeTarget) Skills"
        case .sameSkillSessions, .oldFriend, .focusGoal, .sessionCount:
            return "\(min(safeCurrent, safeTarget)) of \(safeTarget) sessions"
        case .gainLevels:
            return "\(min(safeCurrent, safeTarget)) of \(safeTarget) levels"
        }
    }

    private static func levelsGained(
        between start: Date,
        and end: Date,
        skills: [LifeSkill],
        sessions: [SkillSession]
    ) -> Int {
        let skillsByID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        var secondsBySkill: [UUID: Int] = [:]
        var gained = 0
        for session in sessions.sorted(by: sessionOrder) {
            guard let skill = skillsByID[session.skillID] else { continue }
            let beforeSeconds = secondsBySkill[skill.id, default: 0]
            let afterSeconds = beforeSeconds + max(0, session.activeSeconds)
            secondsBySkill[skill.id] = afterSeconds
            guard start <= session.creditedAt && session.creditedAt < end else { continue }
            let beforeLevel = level(for: skill, seconds: beforeSeconds)
            let afterLevel = level(for: skill, seconds: afterSeconds)
            gained += max(0, afterLevel - beforeLevel)
        }
        return gained
    }

    private static func xpGained(
        for skill: LifeSkill,
        between start: Date,
        and end: Date,
        sessions: [SkillSession]
    ) -> Int {
        var seconds = 0
        var gained = 0
        for session in sessions
            .filter({ $0.skillID == skill.id })
            .sorted(by: sessionOrder) {
            let beforeXP = ProgressionEngine.xp(
                forActiveSeconds: seconds,
                curveVersion: skill.progressionCurveVersion
            )
            seconds += max(0, session.activeSeconds)
            let afterXP = ProgressionEngine.xp(
                forActiveSeconds: seconds,
                curveVersion: skill.progressionCurveVersion
            )
            if start <= session.creditedAt && session.creditedAt < end {
                gained += max(0, afterXP - beforeXP)
            }
        }
        return gained
    }

    private static func progress(
        for skill: LifeSkill,
        sessions: [SkillSession]
    ) -> ProgressSnapshot {
        let seconds = sessions
            .filter { $0.skillID == skill.id }
            .reduce(0) { $0 + max(0, $1.activeSeconds) }
        let xp = ProgressionEngine.xp(
            forActiveSeconds: seconds,
            curveVersion: skill.progressionCurveVersion
        )
        return ProgressionEngine.progress(
            forTotalXP: xp,
            curveVersion: skill.progressionCurveVersion
        )
    }

    private static func level(for skill: LifeSkill, seconds: Int) -> Int {
        let xp = ProgressionEngine.xp(
            forActiveSeconds: seconds,
            curveVersion: skill.progressionCurveVersion
        )
        return ProgressionEngine.level(
            forTotalXP: xp,
            curveVersion: skill.progressionCurveVersion
        )
    }

    private static func preferredSkill(
        from skills: [LifeSkill],
        sessions: [SkillSession]
    ) -> LifeSkill? {
        let totals = Dictionary(grouping: sessions, by: \.skillID)
            .mapValues { matching in
                matching.reduce(0) { $0 + max(0, $1.activeSeconds) }
            }
        return skills.sorted {
            let lhs = totals[$0.id, default: 0]
            let rhs = totals[$1.id, default: 0]
            if lhs != rhs { return lhs > rhs }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }

    private static func oldFriendSkill(
        from skills: [LifeSkill],
        sessions: [SkillSession],
        before date: Date,
        calendar: Calendar
    ) -> LifeSkill? {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: date)
            ?? date.addingTimeInterval(-7 * 86_400)
        var latestBySkill: [UUID: Date] = [:]
        for session in sessions where session.creditedAt < date {
            latestBySkill[session.skillID] = max(
                latestBySkill[session.skillID] ?? .distantPast,
                session.creditedAt
            )
        }
        return skills
            .filter { skill in
                if let latest = latestBySkill[skill.id] {
                    return latest < cutoff
                }
                return skill.createdAt < cutoff
            }
            .sorted {
                let lhs = latestBySkill[$0.id]
                let rhs = latestBySkill[$1.id]
                if lhs != rhs { return (lhs ?? .distantPast) < (rhs ?? .distantPast) }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }

    private static func adaptiveDailySeconds(
        sessions: [SkillSession],
        before date: Date,
        calendar: Calendar
    ) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -28, to: date)
            ?? date.addingTimeInterval(-28 * 86_400)
        let recent = sessions.filter { cutoff <= $0.creditedAt && $0.creditedAt < date }
        let grouped = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.creditedAt) }
        let activeDayAverage = grouped.isEmpty
            ? 30 * 60
            : grouped.values.map { $0.reduce(0) { $0 + max(0, $1.activeSeconds) } }
                .reduce(0, +) / grouped.count
        return rounded(activeDayAverage, increment: 5 * 60, minimum: 20 * 60, maximum: 60 * 60)
    }

    private static func adaptiveWeeklySeconds(
        sessions: [SkillSession],
        before date: Date,
        calendar: Calendar
    ) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -28, to: date)
            ?? date.addingTimeInterval(-28 * 86_400)
        let recentSeconds = sessions
            .filter { cutoff <= $0.creditedAt && $0.creditedAt < date }
            .reduce(0) { $0 + max(0, $1.activeSeconds) }
        let averageWeek = recentSeconds == 0 ? 3 * 3_600 : recentSeconds / 4
        let target = Int(Double(averageWeek) * 1.1)
        return rounded(target, increment: 30 * 60, minimum: 2 * 3_600, maximum: 8 * 3_600)
    }

    private static func adaptiveDeepSessionSeconds(
        sessions: [SkillSession],
        before date: Date
    ) -> Int {
        let recent = sessions
            .filter { $0.creditedAt < date && $0.creditedAt >= date.addingTimeInterval(-28 * 86_400) }
            .map(\.activeSeconds)
            .filter { $0 > 0 }
            .sorted()
        let median = recent.isEmpty ? 45 * 60 : recent[recent.count / 2]
        return rounded(median, increment: 5 * 60, minimum: 30 * 60, maximum: 60 * 60)
    }

    private static func adaptiveWeeklySessionCount(
        sessions: [SkillSession],
        before date: Date
    ) -> Int {
        let recentCount = sessions.filter {
            $0.creditedAt < date && $0.creditedAt >= date.addingTimeInterval(-28 * 86_400)
        }.count
        return min(max(Int(ceil(Double(max(1, recentCount)) / 4)), 3), 10)
    }

    private static func rounded(
        _ value: Int,
        increment: Int,
        minimum: Int,
        maximum: Int
    ) -> Int {
        let safeIncrement = max(1, increment)
        let rounded = Int((Double(value) / Double(safeIncrement)).rounded()) * safeIncrement
        return min(max(rounded, minimum), maximum)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    private static func sameInstant(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.5
    }

    private static func sessionOrder(_ lhs: SkillSession, _ rhs: SkillSession) -> Bool {
        if lhs.creditedAt != rhs.creditedAt {
            return lhs.creditedAt < rhs.creditedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct QuestLiveStatus: Equatable, Sendable {
    let title: String
    let progressLabel: String
    let fractionComplete: Double
    let timerStart: Date?
    let timerEnd: Date?
    let isComplete: Bool
}

@MainActor
enum QuestBoardService {
    @discardableResult
    static func prepareCurrentBoard(
        in modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws -> [QuestStatus] {
        do {
            let skills = try modelContext.fetch(FetchDescriptor<LifeSkill>())
            let sessions = try modelContext.fetch(FetchDescriptor<SkillSession>())
            var assignments = try modelContext.fetch(FetchDescriptor<QuestAssignment>())

            for cadence in QuestCadence.allCases {
                let generated = QuestEngine.makeAssignments(
                    cadence: cadence,
                    skills: skills,
                    sessions: sessions,
                    existingAssignments: assignments,
                    calendar: calendar,
                    now: now
                )
                for assignment in generated {
                    modelContext.insert(assignment)
                    assignments.append(assignment)
                }
            }

            _ = reconcile(
                assignments: assignments,
                skills: skills,
                sessions: sessions,
                triggeringSessionID: nil,
                now: now
            )
            try modelContext.save()
            return QuestEngine.currentStatuses(
                assignments: assignments,
                calendar: calendar,
                now: now
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func ensureCurrentAssignments(
        assignments: inout [QuestAssignment],
        skills: [LifeSkill],
        sessions: [SkillSession],
        in modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        for cadence in QuestCadence.allCases {
            let generated = QuestEngine.makeAssignments(
                cadence: cadence,
                skills: skills,
                sessions: sessions,
                existingAssignments: assignments,
                calendar: calendar,
                now: now
            )
            for assignment in generated {
                modelContext.insert(assignment)
                assignments.append(assignment)
            }
        }
    }

    @discardableResult
    static func reconcile(
        assignments: [QuestAssignment],
        skills: [LifeSkill],
        sessions: [SkillSession],
        triggeringSessionID: UUID?,
        now: Date = .now
    ) -> [QuestStatus] {
        var newlyCompleted: [QuestStatus] = []
        let triggeringSession = triggeringSessionID.flatMap { id in
            sessions.first { $0.id == id }
        }

        for assignment in assignments where !assignment.isRetired {
            let previousValue = assignment.currentValue
            let value = QuestEngine.currentValue(
                for: assignment,
                skills: skills,
                sessions: sessions
            )
            assignment.currentValue = max(0, value)

            guard assignment.completedAt == nil,
                  value >= assignment.targetValue else { continue }

            if let triggeringSession,
               assignment.periodStart <= triggeringSession.creditedAt,
               triggeringSession.creditedAt < assignment.periodEnd,
               previousValue < assignment.targetValue {
                assignment.completedAt = triggeringSession.creditedAt
                assignment.triggeringSessionID = triggeringSession.id
            } else {
                let lastCreditedSession = sessions
                    .filter {
                        assignment.periodStart <= $0.creditedAt
                            && $0.creditedAt < assignment.periodEnd
                    }
                    .max {
                        if $0.creditedAt != $1.creditedAt {
                            return $0.creditedAt < $1.creditedAt
                        }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                assignment.completedAt = lastCreditedSession?.creditedAt ?? now
                assignment.triggeringSessionID = lastCreditedSession?.id
            }

            if let status = QuestEngine.status(assignment) {
                newlyCompleted.append(status)
            }
        }

        return newlyCompleted
    }
}
