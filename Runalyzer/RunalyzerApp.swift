import SwiftUI
import SwiftData

@main
struct RunalyzerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: RunRecord.self, CoachingInsight.self)
    }
}
