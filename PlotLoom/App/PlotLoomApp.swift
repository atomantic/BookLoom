import SwiftUI
import SwiftData
import os

private let appLogger = Logger(subsystem: "net.shadowpuppet.PlotLoom", category: "App")

@main
struct PlotLoomApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PlotLoomAppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(PlotLoomAppDelegate.self) var appDelegate
    #endif

    @State private var memberIdentity = MemberIdentity()
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRaw = AppAppearance.system.rawValue

    private static let appSchema = Schema([
        BookClub.self,
        BookSubmission.self,
        Rating.self,
        BookNote.self,
        ClubMeeting.self,
        MeetingRSVP.self,
        SelectionPoll.self,
        BookVote.self,
        DiscussionPrompt.self,
    ])

    var sharedModelContainer: ModelContainer = {
        if AppLaunchOptions.isSampleDataEnabled {
            let configuration = ModelConfiguration(
                schema: Self.appSchema,
                isStoredInMemoryOnly: true
            )
            let container = try! ModelContainer(for: Self.appSchema, configurations: [configuration])
            ScreenshotSampleData.populate(container: container)
            return container
        }

        let configuration = ModelConfiguration(
            schema: Self.appSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: Self.appSchema, configurations: [configuration])
        } catch {
            appLogger.error("⚠️ ModelContainer init failed: \(error.localizedDescription, privacy: .public) — falling back to in-memory")
            let memoryConfig = ModelConfiguration(schema: Self.appSchema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: Self.appSchema, configurations: [memoryConfig])
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(memberIdentity)
                .preferredColorScheme(AppAppearance.resolved(from: appAppearanceRaw).preferredColorScheme)
                .onContinueUserActivity(ShareAcceptance.activityType) { activity in
                    guard let metadata = ShareAcceptance.metadata(from: activity) else { return }
                    Task { @MainActor in
                        await ShareAcceptance.handleAccept(
                            metadata: metadata,
                            context: sharedModelContainer.mainContext
                        )
                    }
                }
                .task {
                    #if DEBUG
                    await CloudKitSchemaPrimer.runIfRequested(modelContext: sharedModelContainer.mainContext)
                    #endif

                    // Drain any shares that were accepted via the scene/app
                    // delegate before SwiftUI was ready to receive them.
                    let pending = AcceptedShareInbox.shared.drain()
                    for metadata in pending {
                        await ShareAcceptance.handleAccept(
                            metadata: metadata,
                            context: sharedModelContainer.mainContext
                        )
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        #endif
    }
}
