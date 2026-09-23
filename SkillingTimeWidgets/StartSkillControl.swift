import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen, and Action-button control that starts a Skill.
@available(iOS 18.0, *)
struct StartSkillControl: ControlWidget {
    static let kind = "com.projectskillbook.app.start-skill"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent: StartSkillControlConfiguration.self
        ) { configuration in
            ControlWidgetButton(action: StartSkillSessionIntent(skill: configuration.skill)) {
                Label(
                    configuration.skill?.name ?? "Start Skilling",
                    systemImage: configuration.skill?.symbolName ?? "play.circle.fill"
                )
            }
        }
        .displayName("Start a Skill")
        .description("Starts timing a Skill. Without a choice, it continues your most recent Skill.")
    }
}

@available(iOS 18.0, *)
struct StartSkillControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Start a Skill"

    @Parameter(title: "Skill")
    var skill: SkillEntity?

    func perform() async throws -> some IntentResult {
        .result()
    }
}
