import CloudKit
import Foundation
import Observation
import os
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class CloudKitChangeInbox {
    static let shared = CloudKitChangeInbox()

    private(set) var pendingChangeCount = 0

    private init() {}

    func enqueueChangeNotification() {
        pendingChangeCount += 1
    }
}

@MainActor
enum CloudKitChangeNotifications {
    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "CloudKitChangeNotifications")
    private static let privateSubscriptionID = "bookloom-private-member-snapshot-changes"
    private static let sharedSubscriptionID = "bookloom-member-snapshot-changes"
    private static let didSavePrivateSubscriptionKey = "net.shadowpuppet.BookLoom.didSavePrivateMemberSubscription.v3"
    private static let didSaveSharedSubscriptionKey = "net.shadowpuppet.BookLoom.didSaveSharedMemberSubscription.v3"

    static func configureIfNeeded() async {
        guard Features.cloudKitSharing else { return }
        registerForRemoteNotifications()

        let container = CKContainer(identifier: BookLoomCloudKit.containerIdentifier)
        async let privateSave: Void = saveSubscriptionIfNeeded(
            subscriptionID: privateSubscriptionID,
            defaultsKey: didSavePrivateSubscriptionKey,
            databaseName: "private",
            database: container.privateCloudDatabase
        )
        async let sharedSave: Void = saveSubscriptionIfNeeded(
            subscriptionID: sharedSubscriptionID,
            defaultsKey: didSaveSharedSubscriptionKey,
            databaseName: "shared",
            database: container.sharedCloudDatabase
        )
        _ = await (privateSave, sharedSave)
    }

    private static func saveSubscriptionIfNeeded(
        subscriptionID: String,
        defaultsKey: String,
        databaseName: String,
        database: CKDatabase
    ) async {
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        subscription.recordType = CloudKitSharingService.memberSnapshotRecordType

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            UserDefaults.standard.set(true, forKey: defaultsKey)
            logger.info("Saved \(databaseName, privacy: .public) CloudKit member snapshot subscription")
        } catch {
            logger.error("Failed to save \(databaseName, privacy: .public) CloudKit member snapshot subscription: \(CloudKitErrorDescriber.describe(error), privacy: .public)")
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
}
