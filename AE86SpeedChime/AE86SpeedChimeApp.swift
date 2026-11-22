import SwiftUI

@main
struct AE86SpeedChimeApp: App {
    @StateObject private var tracker = SpeedTracker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracker)
                .preferredColorScheme(.dark)
        }
    }
}
