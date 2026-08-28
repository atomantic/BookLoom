import SwiftUI
import SwiftData
import os
#if os(macOS)
import AppKit
#endif

private let appLogger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "App")

enum ModelContainerStorage: Equatable {
    case persistentCloudKit
    case memory
}

@MainActor
protocol ModelContainerBuilding {
    func makeContainer(schema: Schema, storage: ModelContainerStorage) throws -> ModelContainer
}

@MainActor
struct ProductionModelContainerFactory: ModelContainerBuilding {
    func makeContainer(schema: Schema, storage: ModelContainerStorage) throws -> ModelContainer {
        let configuration: ModelConfiguration
        switch storage {
        case .persistentCloudKit:
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        case .memory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

@main
struct BookLoomApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BookLoomAppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(BookLoomAppDelegate.self) var appDelegate
    #endif

    @State private var memberIdentity = MemberIdentity()
    @State private var activeClubStore = ActiveClubStore()
    @State private var goodreadsInbox: GoodreadsImportInbox
    private let acceptedShareInbox = AcceptedShareInbox.shared
    private let cloudKitChangeInbox = CloudKitChangeInbox.shared
    #if os(macOS)
    private let reopenMainWindowInbox = ReopenMainWindowInbox.shared
    @Environment(\.openWindow) private var openWindow
    #endif
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRaw = AppAppearance.system.rawValue
    private let cloudRefreshCoordinator = CloudRefreshCoordinator()

    private let modelBootstrap: ModelBootstrap

    init() {
        LegacyDefaultsMigration.migrateBookLoomKeys()
        let importInboxDefaults = AppLaunchOptions.isSampleDataEnabled ? UserDefaults.standard : SharedImportInbox.defaults
        _goodreadsInbox = State(initialValue: GoodreadsImportInbox(defaults: importInboxDefaults))
        modelBootstrap = Self.makeModelBootstrap()

        #if DEBUG
        if CloudKitSchemaPrimer.isRequested {
            Task { @MainActor in
                await CloudKitSchemaPrimer.runIfRequested()
            }
        }
        #endif
    }

    /// Stable identifier for the primary scene so it can be reopened via
    /// `openWindow(id:)` (Dock click, Show Main Window) and restored reliably.
    private static let mainWindowID = "main"

    static let appSchema = Schema([
        BookClub.self,
        BookSubmission.self,
        LibraryBook.self,
        Rating.self,
        BookNote.self,
        ClubMeeting.self,
        MeetingRSVP.self,
        SelectionPoll.self,
        BookVote.self,
        DiscussionPrompt.self,
    ])

    private static func makeModelBootstrap() -> ModelBootstrap {
        ModelBootstrap.make(
            schema: appSchema,
            sampleDataEnabled: AppLaunchOptions.isSampleDataEnabled,
            factory: ProductionModelContainerFactory(),
            populateSampleData: ScreenshotSampleData.populate
        )
    }

    private var sharedModelContainer: ModelContainer { modelBootstrap.container }

    var body: some Scene {
        WindowGroup("BookLoom", id: Self.mainWindowID) {
            if modelBootstrap.presentation == .recovery,
               let errorMessage = modelBootstrap.errorMessage {
                ModelStoreRecoveryView(errorMessage: errorMessage)
            } else {
                RootView()
                .environment(memberIdentity)
                .environment(activeClubStore)
                .environment(goodreadsInbox)
                .preferredColorScheme(AppAppearance.resolved(from: appAppearanceRaw).preferredColorScheme)
                .modifier(ScreenshotAppearanceOverride())
                .modifier(ScreenshotDynamicTypeOverride())
                #if os(macOS)
                // Gives `.windowResizability(.contentMinSize)` a concrete floor;
                // without a content minimum that modifier has nothing to derive.
                // `.topLeading` so that if content ever exceeds the window it
                // anchors to the top-left and clips off-screen at the trailing
                // edge, rather than centering and hiding the sidebar on the left.
                .frame(minWidth: 800, minHeight: 600, alignment: .topLeading)
                .modifier(ScreenshotWindowFrameOverride())
                #endif
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
                    // Make the free, author-hosted edition discoverable from
                    // the Shelf on a fresh install. Existing Accelerando
                    // entries are recognized so upgrades never duplicate one.
                    _ = try? AccelerandoBook.ensureOnShelf(context: sharedModelContainer.mainContext)

                    #if DEBUG
                    await CloudKitSchemaPrimer.runIfRequested()
                    #endif

                    SchemaPrimeDataCleanup.removeSchemaPrimeData(from: sharedModelContainer.mainContext)
                    CoverDataCleanup.clearPersistedCoverData(in: sharedModelContainer.mainContext)
                    await BookLoomDataReset.retryPendingCloudKitCleanup(context: sharedModelContainer.mainContext)
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
                        await refreshCloudChanges()
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        // Observe at the Scene level, not in the window content: when the last
        // window closes the content view is torn down, which is exactly the
        // Dock-reopen case this bridge handles. A Scene-level onChange survives.
        .onChange(of: reopenMainWindowInbox.reopenRequestCount) { _, _ in
            openWindow(id: Self.mainWindowID)
        }
        .defaultSize(width: 1100, height: 750)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Show Main Window") {
                    openWindow(id: Self.mainWindowID)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
        #endif

        // Separate #if: the modifiers above attach to WindowGroup, while
        // Settings is its own Scene. A merged #if puts a Scene statement after
        // a modifier chain, which the @SceneBuilder #if handling rejects.
        #if os(macOS)
        // Standard Settings scene (Cmd+,). RootView also exposes an in-app
        // Settings tab; both surface the same SettingsView intentionally so the
        // macOS-conventional menu item works without removing the tab that
        // iOS relies on.
        Settings {
            if modelBootstrap.presentation == .recovery,
               let errorMessage = modelBootstrap.errorMessage {
                ModelStoreRecoveryView(errorMessage: errorMessage)
            } else {
                SettingsView()
                    .environment(memberIdentity)
                    .preferredColorScheme(AppAppearance.resolved(from: appAppearanceRaw).preferredColorScheme)
                    .modelContainer(sharedModelContainer)
            }
        }
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

    @MainActor
    private func refreshCloudChanges() async {
        await cloudRefreshCoordinator.request {
            await CloudKitChangeNotifications.refreshSharedClubs(
                in: sharedModelContainer.mainContext,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        }
    }
}

struct ModelBootstrap {
    enum Presentation: Equatable {
        case library
        case recovery
    }

    let container: ModelContainer
    let errorMessage: String?

    var presentation: Presentation {
        errorMessage == nil ? .library : .recovery
    }

    @MainActor
    static func make(
        schema: Schema,
        sampleDataEnabled: Bool,
        factory: any ModelContainerBuilding,
        populateSampleData: (ModelContainer) -> Void = { _ in }
    ) -> ModelBootstrap {
        if sampleDataEnabled {
            do {
                let container = try factory.makeContainer(schema: schema, storage: .memory)
                populateSampleData(container)
                return ModelBootstrap(container: container, errorMessage: nil)
            } catch {
                fatalError("Failed to create sample ModelContainer: \(error)")
            }
        }

        do {
            return ModelBootstrap(
                container: try factory.makeContainer(schema: schema, storage: .persistentCloudKit),
                errorMessage: nil
            )
        } catch {
            appLogger.fault("ModelContainer init failed: \(error.localizedDescription, privacy: .public)")
            // A temporary container exists only so SwiftUI can render the
            // blocking recovery screen. RootView is never mounted, preventing
            // edits that would appear to save but disappear on relaunch.
            do {
                return ModelBootstrap(
                    container: try factory.makeContainer(schema: schema, storage: .memory),
                    errorMessage: error.localizedDescription
                )
            } catch let fallbackError {
                fatalError("Failed to create ModelContainer: \(fallbackError) (original error: \(error))")
            }
        }
    }
}

private struct ModelStoreRecoveryView: View {
    let errorMessage: String

    var body: some View {
        ContentUnavailableView {
            Label("BookLoom couldn't open your library", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Your library is read-only and unavailable because its database could not be opened. Quit BookLoom, make sure this device has free storage and iCloud Drive is available, then reopen the app.\n\n\(errorMessage)")
        }
        .padding(32)
    }
}

#if os(macOS)
private struct ScreenshotWindowFrameOverride: ViewModifier {
    func body(content: Content) -> some View {
        content.task {
            guard AppLaunchOptions.screenshotRoute != nil else { return }
            // Let the window finish materializing before we reposition it.
            try? await Task.sleep(for: .milliseconds(300))
            guard let screen = NSScreen.main,
                  let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
                return
            }

            let visibleFrame = screen.visibleFrame
            let size = NSSize(width: 1440, height: 900)
            let origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - size.height
            )

            window.setFrame(NSRect(origin: origin, size: size), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
#endif

/// Keeps App Store screenshot captures independent from the simulator or
/// developer device appearance setting.
private struct ScreenshotAppearanceOverride: ViewModifier {
    func body(content: Content) -> some View {
        if AppLaunchOptions.screenshotRoute != nil {
            content.preferredColorScheme(.light)
        } else {
            content
        }
    }
}

/// Applies the `-screenshotDynamicType <size>` launch arg as a `dynamicTypeSize`
/// override. No-op when the arg is absent or unrecognized so the user's system
/// setting wins in production.
private struct ScreenshotDynamicTypeOverride: ViewModifier {
    private let resolvedSize: DynamicTypeSize? = .fromScreenshotArgument(AppLaunchOptions.screenshotDynamicType)

    func body(content: Content) -> some View {
        if let resolvedSize {
            content.dynamicTypeSize(resolvedSize)
        } else {
            content
        }
    }
}
