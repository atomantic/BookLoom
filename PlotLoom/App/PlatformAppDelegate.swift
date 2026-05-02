import Foundation
import SwiftUI
import CloudKit
import SwiftData

#if os(iOS)
import UIKit

/// iOS app delegate solely to install a scene delegate. The scene delegate
/// catches CKShare invites accepted on cold launch — SwiftUI's
/// `onContinueUserActivity` is not 100% reliable for cold launches, so we
/// implement both paths per the sharing skill's recommendation.
final class PlotLoomAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = PlotLoomSceneDelegate.self
        return config
    }
}

final class PlotLoomSceneDelegate: NSObject, UIWindowSceneDelegate {
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
final class PlotLoomAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        AcceptedShareInbox.shared.enqueue(metadata)
    }
}
#endif

/// Buffers CKShare metadata that arrived before the SwiftUI scene was ready
/// to accept it. The root view drains the inbox once per appearance.
@MainActor
final class AcceptedShareInbox: ObservableObject {
    static let shared = AcceptedShareInbox()

    @Published private(set) var pending: [CKShare.Metadata] = []

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
