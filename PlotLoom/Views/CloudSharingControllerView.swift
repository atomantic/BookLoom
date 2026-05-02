#if os(iOS)
import SwiftUI
import CloudKit
import UIKit

/// SwiftUI wrapper around `UICloudSharingController` for managing CKShare
/// invites and participant permissions on iOS.
struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("⚠️ CKShare save failed: \(error.localizedDescription)")
        }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            controller.share?[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {}
        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {}
    }
}
#endif
