import SwiftData
import SwiftUI

@main
struct SkillingTimeApp: App {
    @StateObject private var sessionController = SessionController()
    @StateObject private var liveActivityCoordinator = LiveActivityCoordinator()
    @StateObject private var notificationManager = ProgressionNotificationManager()

    private let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SkillingTimeSchemaV4.self)

        // Keep the legacy store configuration name so upgrades from Skillbook
        // retain all existing SwiftData history after the Skilling Time rebrand.
        let configuration = ModelConfiguration(
            "Skillbook",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SkillingTimeMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Unable to initialize Skilling Time storage: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(sessionController)
                .environmentObject(liveActivityCoordinator)
                .environmentObject(notificationManager)
        }
        .modelContainer(modelContainer)
    }
}
