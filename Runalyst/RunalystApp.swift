import SwiftUI
import SwiftData

@main
struct RunalystApp: App {

    let container: ModelContainer = {
        print("DEBUG: Starting ModelContainer initialization")
        let schema = Schema([
            RunRecord.self,
            CoachingInsight.self,
            DrillRecommendation.self,
            TrainingCorrection.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            print("DEBUG: Attempting to create container")
            let c = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("DEBUG: Created container successfully")
            return c
        } catch {
            print("DEBUG: Failed to load ModelContainer, attempting to delete old store: \(error)")
            let storeURL = modelConfiguration.url
            let storePath = storeURL.path
            let shmPath = storePath + "-shm"
            let walPath = storePath + "-wal"
            
            try? FileManager.default.removeItem(atPath: storePath)
            try? FileManager.default.removeItem(atPath: shmPath)
            try? FileManager.default.removeItem(atPath: walPath)
            
            do {
                print("DEBUG: Retrying container creation")
                let c = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("DEBUG: Re-created container successfully")
                return c
            } catch {
                fatalError("Could not create ModelContainer even after wiping store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
