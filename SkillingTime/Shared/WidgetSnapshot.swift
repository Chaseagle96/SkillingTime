import Foundation

/// One Skill as the widgets, Control Center control, and Siri see it. Written by
/// the app into the App Group so extensions never open the SwiftData store.
struct WidgetSkillSummary: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let symbolName: String
    let accentHex: String
    let level: Int
    let fractionToNextLevel: Double
    /// Practice time still needed for the next level (or Mastery star); nil when
    /// nothing is left to earn.
    let secondsToNextLevel: Int?
    let latestSessionAt: Date?
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let formatVersion = 1

    var version = WidgetSnapshot.formatVersion
    let generatedAt: Date
    /// Active (not retired) Skills in Skillbook order.
    let skills: [WidgetSkillSummary]
    let dayStart: Date
    let todaySeconds: Int
    let todayXP: Int
    /// Active seconds for the last seven days, oldest first, ending with `dayStart`.
    let weekDaySeconds: [Int]

    /// Today's totals only apply while it is still the day they were written.
    func todaySeconds(at date: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(dayStart, inSameDayAs: date) ? todaySeconds : 0
    }

    func todayXP(at date: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(dayStart, inSameDayAs: date) ? todayXP : 0
    }

    /// The practiced Skill closest to its next level.
    var closestToLevel: WidgetSkillSummary? {
        skills
            .filter { $0.latestSessionAt != nil && $0.secondsToNextLevel != nil }
            .min { ($0.secondsToNextLevel ?? .max) < ($1.secondsToNextLevel ?? .max) }
    }

    /// Most recently practiced first; never-practiced Skills keep Skillbook order.
    var recentSkills: [WidgetSkillSummary] {
        skills.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.latestSessionAt, rhs.element.latestSessionAt) {
                case let (left?, right?): return left > right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}

enum WidgetSnapshotStore {
    static let snapshotKey = "skillingtime.widget-snapshot.v1"
    static let pendingStartKey = "skillingtime.pending-start.v1"

    static func load(
        from defaults: UserDefaults = SkillingTimeSharedConfiguration.makeSharedDefaults()
    ) -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns true when the stored snapshot changed (so callers reload widgets only then).
    @discardableResult
    static func save(
        _ snapshot: WidgetSnapshot,
        to defaults: UserDefaults = SkillingTimeSharedConfiguration.makeSharedDefaults()
    ) -> Bool {
        if let existing = load(from: defaults), existing.isSameContent(as: snapshot) {
            return false
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }

    /// Widgets, the Control Center control, and Siri ask the app to start a Skill
    /// by leaving a request here; the app starts it when it becomes active.
    static func requestStart(
        skillID: UUID,
        at date: Date = .now,
        defaults: UserDefaults = SkillingTimeSharedConfiguration.makeSharedDefaults()
    ) {
        defaults.set(
            ["skillID": skillID.uuidString, "requestedAt": date.timeIntervalSince1970],
            forKey: pendingStartKey
        )
    }

    /// Consumes a pending start request. Requests older than `maximumAge` are
    /// dropped so a stale tap never starts a timer much later.
    static func takePendingStart(
        at date: Date = .now,
        maximumAge: TimeInterval = 10 * 60,
        defaults: UserDefaults = SkillingTimeSharedConfiguration.makeSharedDefaults()
    ) -> UUID? {
        guard let request = defaults.dictionary(forKey: pendingStartKey) else { return nil }
        defaults.removeObject(forKey: pendingStartKey)
        guard let rawID = request["skillID"] as? String,
              let skillID = UUID(uuidString: rawID),
              let requestedAt = request["requestedAt"] as? Double,
              date.timeIntervalSince1970 - requestedAt <= maximumAge else { return nil }
        return skillID
    }
}

private extension WidgetSnapshot {
    func isSameContent(as other: WidgetSnapshot) -> Bool {
        version == other.version
            && skills == other.skills
            && dayStart == other.dayStart
            && todaySeconds == other.todaySeconds
            && todayXP == other.todayXP
            && weekDaySeconds == other.weekDaySeconds
    }
}
