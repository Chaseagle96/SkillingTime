import AppIntents

/// Siri phrases and the Shortcuts app / Action button entry for starting a Skill.
struct SkillingTimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSkillSessionIntent(),
            phrases: [
                "Start \(\.$skill) in \(.applicationName)",
                "Time \(\.$skill) with \(.applicationName)",
                "Start skilling in \(.applicationName)"
            ],
            shortTitle: "Start a Skill",
            systemImageName: "play.circle.fill"
        )
    }
}
