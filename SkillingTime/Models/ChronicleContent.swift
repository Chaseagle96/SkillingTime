import Foundation

struct ChronicleEntry: Identifiable, Sendable {
    let level: Int
    let rank: SkillRank
    let chapter: String
    let passage: String
    let unlockTitle: String
    let unlockDescription: String

    var id: Int { level }
}

enum ChronicleContent {
    static let entries: [ChronicleEntry] = [
        ChronicleEntry(
            level: 25,
            rank: .apprentice,
            chapter: "I · Familiar Hands",
            passage: "What once required thought is beginning to become instinct. You have returned to the work often enough that your hands now remember what your mind once had to command.",
            unlockTitle: "Focus Goals",
            unlockDescription: "Set a duration, XP, or progression target before beginning this Skill."
        ),
        ChronicleEntry(
            level: 50,
            rank: .journeyman,
            chapter: "II · The Craft",
            passage: "Practice has become familiarity, and familiarity has begun to become craft. There are things you once had to remember that you now simply know. The work remains, but you no longer meet it as a stranger.",
            unlockTitle: "Specialization",
            unlockDescription: "Give this Skill a custom identity such as Home Cook, Bread Maker, or a title of your own."
        ),
        ChronicleEntry(
            level: 75,
            rank: .expert,
            chapter: "III · Distinctions",
            passage: "You can now see distinctions that were once invisible to you. The work has not become smaller. You have become more capable of meeting it.",
            unlockTitle: "Expert Challenges",
            unlockDescription: "Choose a substantial 30-day undertaking and earn a permanent Character title when it is completed."
        ),
        ChronicleEntry(
            level: 100,
            rank: .master,
            chapter: "IV · Mastery",
            passage: "There was never a shortcut hidden from you. Time, repetition, attention, and the decision to return were the secret all along. What began as something you did has become part of who you are.",
            unlockTitle: "Legacy",
            unlockDescription: "Create a permanent Master title and crest while continuing through unlimited Mastery stars."
        )
    ]

    static func entry(for level: Int) -> ChronicleEntry? {
        entries.first { $0.level == level }
    }
}
