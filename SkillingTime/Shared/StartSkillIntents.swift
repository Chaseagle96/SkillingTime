import AppIntents
import Foundation

/// A Skill as Siri, Shortcuts, widgets, and the Control Center control see it.
/// Resolved from the App Group snapshot, so it works in the widget extension too.
struct SkillEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Skill"
    static let defaultQuery = SkillEntityQuery()

    let id: UUID
    let name: String
    let symbolName: String

    init(id: UUID, name: String, symbolName: String) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }

    init(summary: WidgetSkillSummary) {
        self.init(id: summary.id, name: summary.name, symbolName: summary.symbolName)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: symbolName)
        )
    }
}

struct SkillEntityQuery: EntityStringQuery {
    private var skills: [WidgetSkillSummary] {
        WidgetSnapshotStore.load()?.recentSkills ?? []
    }

    func entities(for identifiers: [UUID]) async throws -> [SkillEntity] {
        let known = skills
        return identifiers.compactMap { identifier in
            known.first { $0.id == identifier }.map(SkillEntity.init(summary:))
        }
    }

    func entities(matching string: String) async throws -> [SkillEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return skills
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .map(SkillEntity.init(summary:))
    }

    func suggestedEntities() async throws -> [SkillEntity] {
        skills.map(SkillEntity.init(summary:))
    }
}

enum StartSkillIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noSkills

    var localizedStringResource: LocalizedStringResource {
        "Open Skilling Time once so your Skills are available here."
    }
}

/// Opens Skilling Time and starts timing a Skill. The request is handed to the
/// app through the App Group, so it works from Siri, Shortcuts, the Action
/// button, widgets, and the Control Center control alike.
struct StartSkillSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Skill Session"
    static let description = IntentDescription("Starts timing a Skill in Skilling Time.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Skill")
    var skill: SkillEntity?

    init() {}

    init(skill: SkillEntity?) {
        self.skill = skill
    }

    func perform() async throws -> some IntentResult {
        // Without a choice, continue with the most recently practiced Skill.
        guard let skillID = skill?.id ?? WidgetSnapshotStore.load()?.recentSkills.first?.id else {
            throw StartSkillIntentError.noSkills
        }
        WidgetSnapshotStore.requestStart(skillID: skillID)
        return .result()
    }
}
