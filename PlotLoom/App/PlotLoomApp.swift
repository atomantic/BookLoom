import SwiftUI
import SwiftData
import os

private let appLogger = Logger(subsystem: "net.shadowpuppet.PlotLoom", category: "App")

@main
struct PlotLoomApp: App {
    @State private var memberIdentity = MemberIdentity()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BookClub.self,
            BookSubmission.self,
            Rating.self,
            BookNote.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            appLogger.error("⚠️ ModelContainer init failed: \(error.localizedDescription, privacy: .public) — falling back to in-memory")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memoryConfig])
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(memberIdentity)
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        #endif
    }
}
