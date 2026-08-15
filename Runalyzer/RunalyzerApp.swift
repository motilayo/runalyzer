import SwiftUI
import SwiftData

@main
struct RunalyzerApp: App {

    let container: ModelContainer = {
        let schema = Schema([
            RunRecord.self,
            CoachingInsight.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
