import SwiftUI

@main
struct SkillingTimeWatchApp: App {
    @StateObject private var watchConnectivity = SkillingTimeWatchConnectivity()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(watchConnectivity)
        }
    }
}
