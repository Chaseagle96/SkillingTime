import SwiftData
import SwiftUI

@main
struct SkillingTimeApp: App {
    @StateObject private var sessionController = SessionController()
    @StateObject private var liveActivityCoordinator = LiveActivityCoordinator()
    @StateObject private var notificationManager = ProgressionNotificationManager()
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.defaultValue.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .defaultValue
    }

    /// Opening the store can fail (for example after an interrupted migration).
    /// Instead of crashing on every launch, a failure shows a recovery screen that
    /// leaves the files untouched and lets the person export them.
    private let storage: Result<ModelContainer, Error> = {
        let schema = Schema(versionedSchema: SkillingTimeSchemaV5.self)

        // Keep the legacy store configuration name so upgrades from Skillbook
        // retain all existing SwiftData history after the Skilling Time rebrand.
        let configuration = ModelConfiguration(
            "Skillbook",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return .success(
                try ModelContainer(
                    for: schema,
                    migrationPlan: SkillingTimeMigrationPlan.self,
                    configurations: [configuration]
                )
            )
        } catch {
            return .failure(error)
        }
    }()

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                LaunchExperienceContainer {
                    RootTabView()
                }
                .environmentObject(sessionController)
                .environmentObject(liveActivityCoordinator)
                .environmentObject(notificationManager)
                .modelContainer(container)
                // Read once at the root so the launch screen, every screen, and
                // every sheet follow the chosen appearance.
                .environment(\.skillingTimeAppearance, appearance)
                .preferredColorScheme(appearance.colorScheme)
            case .failure(let error):
                StorageRecoveryView(errorDescription: String(describing: error))
            }
        }
    }
}

private struct StorageRecoveryView: View {
    let errorDescription: String

    /// SwiftData keeps a named configuration's files in Application Support,
    /// prefixed with the configuration name (the store plus its -wal/-shm files).
    private var storeFiles: [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: URL.applicationSupportDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("Skillbook") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(
                        "Your Skillbook could not be opened",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SkillingTimeTheme.gold)

                    Text(
                        "Skilling Time did not change or delete anything. Your history is still on this device. Export the data files and keep them somewhere safe before updating or reinstalling."
                    )

                    let files = storeFiles
                    if files.isEmpty {
                        Text("No data files were found to export.")
                            .foregroundStyle(.secondary)
                    } else {
                        ShareLink(items: files) {
                            Label("Export Data Files", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SkillingTimeTheme.gold)
                    }

                    Text("Details")
                        .font(.headline)
                    Text(errorDescription)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Skilling Time")
            .skillingTimeScreenBackground()
        }
        .preferredColorScheme(.dark)
    }
}
