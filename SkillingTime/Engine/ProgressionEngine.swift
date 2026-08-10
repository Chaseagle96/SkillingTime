import Foundation

enum SkillRank: String, CaseIterable, Codable, Sendable {
    case novice = "Novice"
    case apprentice = "Apprentice"
    case journeyman = "Journeyman"
    case expert = "Expert"
    case master = "Master"

    var levelRange: ClosedRange<Int> {
        switch self {
        case .novice: 1...24
        case .apprentice: 25...49
        case .journeyman: 50...74
        case .expert: 75...99
        case .master: 100...100
        }
    }
}

enum ProgressionCurveVersion: Int, CaseIterable, Codable, Sendable {
    case v1 = 1
}

struct ProgressSnapshot: Equatable, Sendable {
    let totalXP: Int
    let level: Int
    let rank: SkillRank
    let currentLevelXP: Int
    let nextLevelXP: Int
    let xpRemaining: Int
    let fractionComplete: Double
    let masteryStars: Int

    var displayRank: String {
        masteryStars > 0 ? "Mastery \(masteryStars.romanNumeral)" : rank.rawValue
    }
}

private protocol ProgressionCurve: Sendable {
    var version: ProgressionCurveVersion { get }
    var xpPerMinute: Int { get }
    var secondsPerXP: Int { get }
    var maximumLevel: Int { get }
    var masteryHoursPerStar: Int { get }

    func xpToAdvance(from level: Int) -> Int
}

private struct ProgressionCurveV1: ProgressionCurve {
    let version = ProgressionCurveVersion.v1
    let xpPerMinute = 20
    let secondsPerXP = 3
    let maximumLevel = 100
    let masteryHoursPerStar = 25

    func xpToAdvance(from level: Int) -> Int {
        guard level >= 1, level < maximumLevel else { return 0 }
        let exponential = 100 * pow(1.045, Double(level - 1))
        return Int((exponential + (15 * Double(level))).rounded())
    }
}

private enum ProgressionCurveRegistry {
    private static let versionOne = ProgressionCurveV1()
    private static let versionOneThresholds = makeThresholds(for: versionOne)

    static func curve(for rawVersion: Int) -> any ProgressionCurve {
        guard let version = ProgressionCurveVersion(rawValue: rawVersion) else {
            preconditionFailure("Unsupported progression curve version: \(rawVersion)")
        }

        switch version {
        case .v1:
            return versionOne
        }
    }

    static func cumulativeThresholds(for rawVersion: Int) -> [Int] {
        guard let version = ProgressionCurveVersion(rawValue: rawVersion) else {
            preconditionFailure("Unsupported progression curve version: \(rawVersion)")
        }

        switch version {
        case .v1:
            return versionOneThresholds
        }
    }

    private static func makeThresholds(for curve: any ProgressionCurve) -> [Int] {
        var thresholds = Array(repeating: 0, count: curve.maximumLevel + 1)
        guard curve.maximumLevel > 1 else { return thresholds }

        for level in 2...curve.maximumLevel {
            thresholds[level] = thresholds[level - 1]
                + curve.xpToAdvance(from: level - 1)
        }
        return thresholds
    }
}

enum ProgressionEngine {
    static let currentCurveVersion = ProgressionCurveVersion.v1.rawValue

    static func isSupported(curveVersion: Int) -> Bool {
        ProgressionCurveVersion(rawValue: curveVersion) != nil
    }

    static func xpPerMinute(curveVersion: Int) -> Int {
        ProgressionCurveRegistry.curve(for: curveVersion).xpPerMinute
    }

    static func secondsPerXP(curveVersion: Int) -> Int {
        ProgressionCurveRegistry.curve(for: curveVersion).secondsPerXP
    }

    static func maximumLevel(curveVersion: Int) -> Int {
        ProgressionCurveRegistry.curve(for: curveVersion).maximumLevel
    }

    static func masteryHoursPerStar(curveVersion: Int) -> Int {
        ProgressionCurveRegistry.curve(for: curveVersion).masteryHoursPerStar
    }

    static func masteryXPPerStar(curveVersion: Int) -> Int {
        let curve = ProgressionCurveRegistry.curve(for: curveVersion)
        return curve.masteryHoursPerStar * 60 * curve.xpPerMinute
    }

    static func xp(forActiveSeconds seconds: Int, curveVersion: Int) -> Int {
        let curve = ProgressionCurveRegistry.curve(for: curveVersion)
        return max(0, seconds) / curve.secondsPerXP
    }

    static func xpToAdvance(from level: Int, curveVersion: Int) -> Int {
        ProgressionCurveRegistry.curve(for: curveVersion).xpToAdvance(from: level)
    }

    static func cumulativeXP(toReach level: Int, curveVersion: Int) -> Int {
        let curve = ProgressionCurveRegistry.curve(for: curveVersion)
        let clampedLevel = min(max(level, 1), curve.maximumLevel)
        return ProgressionCurveRegistry.cumulativeThresholds(for: curveVersion)[clampedLevel]
    }

    static func level(forTotalXP xp: Int, curveVersion: Int) -> Int {
        let curve = ProgressionCurveRegistry.curve(for: curveVersion)
        let thresholds = ProgressionCurveRegistry.cumulativeThresholds(for: curveVersion)
        let safeXP = max(0, xp)
        var lower = 1
        var upper = curve.maximumLevel

        while lower < upper {
            let midpoint = (lower + upper + 1) / 2
            if thresholds[midpoint] <= safeXP {
                lower = midpoint
            } else {
                upper = midpoint - 1
            }
        }

        return lower
    }

    static func rank(for level: Int) -> SkillRank {
        switch level {
        case ..<25: .novice
        case 25..<50: .apprentice
        case 50..<75: .journeyman
        case 75..<100: .expert
        default: .master
        }
    }

    static func progress(forTotalXP xp: Int, curveVersion: Int) -> ProgressSnapshot {
        let curve = ProgressionCurveRegistry.curve(for: curveVersion)
        let safeXP = max(0, xp)
        let level = level(forTotalXP: safeXP, curveVersion: curveVersion)
        let rank = rank(for: level)

        if level == curve.maximumLevel {
            let levelCapXP = cumulativeXP(toReach: curve.maximumLevel, curveVersion: curveVersion)
            let masteryXP = max(0, safeXP - levelCapXP)
            let starXP = masteryXPPerStar(curveVersion: curveVersion)
            let stars = masteryXP / starXP
            let withinStar = masteryXP % starXP
            let remaining = starXP - withinStar

            return ProgressSnapshot(
                totalXP: safeXP,
                level: level,
                rank: rank,
                currentLevelXP: withinStar,
                nextLevelXP: starXP,
                xpRemaining: remaining,
                fractionComplete: Double(withinStar) / Double(starXP),
                masteryStars: stars
            )
        }

        let levelStart = cumulativeXP(toReach: level, curveVersion: curveVersion)
        let levelEnd = cumulativeXP(toReach: level + 1, curveVersion: curveVersion)
        let earned = safeXP - levelStart
        let required = levelEnd - levelStart

        return ProgressSnapshot(
            totalXP: safeXP,
            level: level,
            rank: rank,
            currentLevelXP: earned,
            nextLevelXP: required,
            xpRemaining: max(0, required - earned),
            fractionComplete: required == 0 ? 1 : Double(earned) / Double(required),
            masteryStars: 0
        )
    }

    static func milestonesCrossed(fromXP: Int, toXP: Int, curveVersion: Int) -> [Int] {
        let startingLevel = level(forTotalXP: fromXP, curveVersion: curveVersion)
        let endingLevel = level(forTotalXP: toXP, curveVersion: curveVersion)
        return [25, 50, 75, 100].filter { startingLevel < $0 && endingLevel >= $0 }
    }

    static func levelsCrossed(fromXP: Int, toXP: Int, curveVersion: Int) -> ClosedRange<Int>? {
        let startingLevel = level(forTotalXP: fromXP, curveVersion: curveVersion)
        let endingLevel = level(forTotalXP: toXP, curveVersion: curveVersion)
        guard endingLevel > startingLevel else { return nil }
        return (startingLevel + 1)...endingLevel
    }

    static func nextThresholdXP(after progress: ProgressSnapshot, curveVersion: Int) -> Int {
        if progress.level < maximumLevel(curveVersion: curveVersion) {
            return cumulativeXP(toReach: progress.level + 1, curveVersion: curveVersion)
        }

        let cap = cumulativeXP(
            toReach: maximumLevel(curveVersion: curveVersion),
            curveVersion: curveVersion
        )
        return cap + ((progress.masteryStars + 1) * masteryXPPerStar(curveVersion: curveVersion))
    }
}

private extension Int {
    var romanNumeral: String {
        guard self > 0 else { return "0" }
        let values = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var remaining = self
        var result = ""
        for (value, symbol) in values {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }
}
