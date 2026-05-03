import CloudKit
import Foundation
import os
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class CloudKitChangeInbox: ObservableObject {
    static let shared = CloudKitChangeInbox()

    @Published private(set) var pendingChangeCount = 0

    private init() {}

    func enqueueChangeNotification() {
        pendingChangeCount += 1
    }
}

@MainActor
enum CloudKitChangeNotifications {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "CloudKitChangeNotifications")
    private static let containerID = "iCloud.net.shadowpuppet.PlotLoom"
    private static let sharedSubscriptionID = "bookloom-member-snapshot-changes"
    private static let didSaveSharedSubscriptionKey = "net.shadowpuppet.BookLoom.didSaveSharedRootSubscription.v2"
    private static let memberSnapshotRecordType = "MemberShareSnapshot"

    static func configureIfNeeded() async {
        guard Features.cloudKitSharing, !AppLaunchOptions.isSampleDataEnabled, !isRunningTests else { return }
        registerForRemoteNotifications()

        guard !UserDefaults.standard.bool(forKey: didSaveSharedSubscriptionKey) else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: sharedSubscriptionID)
        subscription.recordType = memberSnapshotRecordType

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await CKContainer(identifier: containerID)
                .sharedCloudDatabase
                .modifySubscriptions(saving: [subscription], deleting: [])
            UserDefaults.standard.set(true, forKey: didSaveSharedSubscriptionKey)
            logger.info("Saved shared CloudKit change subscription")
        } catch {
            logger.error("Failed to save shared CloudKit change subscription: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
        }
    }

    static func refreshSharedClubs(in context: ModelContext, localMemberID: String, localMemberName: String) async {
        do {
            let clubs = try context.fetch(FetchDescriptor<BookClub>())
            await SharedClubSync.refreshIfNeeded(clubs, context: context, localMemberID: localMemberID, localMemberName: localMemberName)
        } catch {
            logger.error("Failed to fetch clubs for CloudKit change refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications(matching: [])
        #endif
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
