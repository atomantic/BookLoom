import Foundation
import Observation
import SwiftUI
import CloudKit
import SwiftData

#if os(iOS)
import UIKit

/// iOS app delegate solely to install a scene delegate. The scene delegate
/// catches CKShare invites accepted on cold launch — SwiftUI's
/// `onContinueUserActivity` is not 100% reliable for cold launches, so we
/// implement both paths per the sharing skill's recommendation.
final class BookLoomAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = BookLoomSceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if CKNotification(fromRemoteNotificationDictionary: userInfo) != nil {
            CloudKitChangeInbox.shared.enqueueChangeNotification()
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
}

final class BookLoomSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        AcceptedShareInbox.shared.enqueue(metadata)
    }
}
#endif

#if os(macOS)
import AppKit

/// macOS app delegate equivalent. Catches CKShare invites accepted on cold
/// launch via the `application(_:userDidAcceptCloudKitShareWith:)` callback.
final class BookLoomAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        AcceptedShareInbox.shared.enqueue(metadata)
    }

    /// Keep the app alive in the Dock when the last window is closed, matching
    /// standard macOS document/utility behavior (App Store Guideline 4).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Re-open the main window when the user clicks the Dock icon after closing
    /// every window. AppKit only restores a visible window when one exists, so
    /// we surface the request and let SwiftUI reopen the scene.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ReopenMainWindowInbox.shared.requestReopen()
        }
        return true
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        if CKNotification(fromRemoteNotificationDictionary: userInfo) != nil {
            CloudKitChangeInbox.shared.enqueueChangeNotification()
        }
    }
}

/// Bridges AppKit Dock-reopen and "Show Main Window" menu requests to SwiftUI,
/// which owns the scene and can reopen it via `openWindow(id:)`.
@MainActor
@Observable
final class ReopenMainWindowInbox {
    static let shared = ReopenMainWindowInbox()

    /// Incremented on each reopen request so SwiftUI's `onChange` fires even for
    /// back-to-back requests.
    private(set) var reopenRequestCount = 0

    private init() {}

    func requestReopen() {
        reopenRequestCount += 1
    }
}
#endif

/// Buffers CKShare metadata that arrived before the SwiftUI scene was ready
/// to accept it. The root view drains the inbox once per appearance.
@MainActor
@Observable
final class AcceptedShareInbox {
    static let shared = AcceptedShareInbox()

    private(set) var pending: [CKShare.Metadata] = []

    private init() {}

    func enqueue(_ metadata: CKShare.Metadata) {
        pending.append(metadata)
    }

    func drain() -> [CKShare.Metadata] {
        let snapshot = pending
        pending.removeAll()
        return snapshot
    }
}
