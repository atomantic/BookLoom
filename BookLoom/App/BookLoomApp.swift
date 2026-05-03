import SwiftUI
import SwiftData
import os

private let appLogger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "App")

@main
struct BookLoomApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BookLoomAppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(BookLoomAppDelegate.self) var appDelegate
    #endif

    @State private var memberIdentity = MemberIdentity()
    @StateObject private var acceptedShareInbox = AcceptedShareInbox.shared
    @StateObject private var cloudKitChangeInbox = CloudKitChangeInbox.shared
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRaw = AppAppearance.system.rawValue

    init() {
        LegacyDefaultsMigration.migrateBookLoomKeys()
    }

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
                            context: sharedModelContainer.mainContext,
                            localMemberID: memberIdentity.memberID,
                            localMemberName: memberIdentity.name
                        )
                    }
                }
                .task {
                    #if DEBUG
                    await CloudKitSchemaPrimer.runIfRequested()
                    #endif

                    SchemaPrimeDataCleanup.removeSchemaPrimeData(from: sharedModelContainer.mainContext)
                    CoverDataCleanup.clearPersistedCoverData(in: sharedModelContainer.mainContext)
                    await drainAcceptedShares()
                    await CloudKitChangeNotifications.configureIfNeeded()
                    await SharedClubSync.synchronizeSharedClubs(
                        in: sharedModelContainer.mainContext,
                        localMemberID: memberIdentity.memberID,
                        localMemberName: memberIdentity.name
                    )
                }
                .onChange(of: acceptedShareInbox.pending.count) { _, _ in
                    Task { @MainActor in
                        await drainAcceptedShares()
                    }
                }
                .onChange(of: cloudKitChangeInbox.pendingChangeCount) { _, _ in
                    Task { @MainActor in
                        await CloudKitChangeNotifications.refreshSharedClubs(
                            in: sharedModelContainer.mainContext,
                            localMemberID: memberIdentity.memberID,
                            localMemberName: memberIdentity.name
                        )
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        #endif
    }

    @MainActor
    private func drainAcceptedShares() async {
        // Drain any shares that were accepted via the scene/app delegate before
        // SwiftUI was ready, and also shares that arrive after the first task.
        let pending = AcceptedShareInbox.shared.drain()
        for metadata in pending {
            await ShareAcceptance.handleAccept(
                metadata: metadata,
                context: sharedModelContainer.mainContext,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        }
    }
}
