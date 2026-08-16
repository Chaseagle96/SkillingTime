import WatchKit

enum SkillingTimeWatchHaptics {
    static func started() {
        WKInterfaceDevice.current().play(.start)
    }

    static func paused() {
        WKInterfaceDevice.current().play(.click)
    }

    static func completed() {
        WKInterfaceDevice.current().play(.success)
    }

    static func failed() {
        WKInterfaceDevice.current().play(.failure)
    }
}
