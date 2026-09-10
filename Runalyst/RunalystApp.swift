import SwiftUI
import SwiftData

@main
struct RunalystApp: App {

    let container: ModelContainer = {
        print("DEBUG: Starting ModelContainer initialization with RunalystMigrationPlan")
        let schema = Schema(versionedSchema: RunalystSchemaV1.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            print("DEBUG: Attempting to create container with migration plan")
            let modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: RunalystMigrationPlan.self,
                configurations: [modelConfiguration]
            )
            print("DEBUG: Created container successfully with migration plan")
            return modelContainer
        } catch {
            print("ERROR: Failed to load persistent ModelContainer with migration plan: \(error)")

            #if DEBUG
            print("DEBUG: Development mode fallback - recreating store: \(error)")
            let storeURL = modelConfiguration.url
            let storePath = storeURL.path
            let shmPath = storePath + "-shm"
            let walPath = storePath + "-wal"

            try? FileManager.default.removeItem(atPath: storePath)
            try? FileManager.default.removeItem(atPath: shmPath)
            try? FileManager.default.removeItem(atPath: walPath)

            if let fallbackContainer = try? ModelContainer(
                for: schema,
                migrationPlan: RunalystMigrationPlan.self,
                configurations: [modelConfiguration]
            ) {
                print("DEBUG: Re-created container successfully after recovery")
                return fallbackContainer
            }
            #endif

            print("WARNING: Falling back to in-memory ModelContainer to prevent user data crash")
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let inMemoryContainer = try? ModelContainer(for: schema, configurations: [inMemoryConfig]) {
                return inMemoryContainer
            }

            fatalError("Unrecoverable SwiftData initialization failure: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
