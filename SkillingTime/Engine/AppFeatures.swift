import Foundation

/// Switchboard for the simplified Skilling Time. Features turned off here are
/// hidden, not removed: their engines keep running and their records stay in the
/// store and in backups, so turning a value back on restores the feature with its
/// full history. Delete code only once the simplified app has proven itself.
enum AppFeatures {
    /// Separate Today tab. Off: the Skills tab is home and shows today at the top.
    static let todayTab = false
    /// Daily and weekly Quests (they lived on the Today tab and the Live Activity).
    static let quests = false
    /// Character Paths, Path levels and titles, and the Path review.
    static let characterPaths = false
    /// Specializations (Level 50), Expert Challenges (75), and Legacies (100).
    static let lateGameCapabilities = false
    /// Choosing a goal before a session (Level 25).
    static let focusGoals = false
    /// The Achievements gallery. Milestone chapters stay.
    static let achievementsGallery = false

    static func isVisible(_ capability: SkillCapability) -> Bool {
        switch capability {
        case .focusGoals: focusGoals
        case .specialization, .expertChallenge, .legacy: lateGameCapabilities
        }
    }

    /// What a session summary reveals. Hidden systems still record their results.
    static func visibleOutcome(_ outcome: SessionOutcome) -> SessionOutcome {
        SessionOutcome(
            id: outcome.id,
            skillID: outcome.skillID,
            skillName: outcome.skillName,
            symbolName: outcome.symbolName,
            accentHex: outcome.accentHex,
            durationSeconds: outcome.durationSeconds,
            xpEarned: outcome.xpEarned,
            startingProgress: outcome.startingProgress,
            endingProgress: outcome.endingProgress,
            levelsCrossed: outcome.levelsCrossed,
            chroniclesUnlocked: outcome.chroniclesUnlocked,
            achievementsUnlocked: achievementsGallery ? outcome.achievementsUnlocked : [],
            questsCompleted: quests ? outcome.questsCompleted : [],
            personalRecords: outcome.personalRecords,
            pathProgress: characterPaths ? outcome.pathProgress : nil,
            characterTitlesUnlocked: characterPaths ? outcome.characterTitlesUnlocked : [],
            expertChallengesCompleted: lateGameCapabilities ? outcome.expertChallengesCompleted : [],
            capabilitiesUnlocked: outcome.capabilitiesUnlocked.filter(isVisible),
            focusGoalResult: focusGoals ? outcome.focusGoalResult : nil,
            note: outcome.note,
            wasAlreadyCommitted: outcome.wasAlreadyCommitted
        )
    }
}
