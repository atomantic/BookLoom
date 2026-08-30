#if os(iOS)
import SwiftUI
import CloudKit
import UIKit
import os

/// SwiftUI wrapper around `UICloudSharingController` for managing CKShare
/// invites and participant permissions on iOS.
struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onSaveFailure: (Error) -> Void
    let onShareSaved: (CKShare) -> Void
    let onSharingStopped: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            share: share,
            onSaveFailure: onSaveFailure,
            onShareSaved: onShareSaved,
            onSharingStopped: onSharingStopped
        )
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "CloudSharing")
        private let share: CKShare
        private let onSaveFailure: (Error) -> Void
        private let onShareSaved: (CKShare) -> Void
        private let onSharingStopped: () -> Void

        init(
            share: CKShare,
            onSaveFailure: @escaping (Error) -> Void,
            onShareSaved: @escaping (CKShare) -> Void,
            onSharingStopped: @escaping () -> Void
        ) {
            self.share = share
            self.onSaveFailure = onSaveFailure
            self.onShareSaved = onShareSaved
            self.onSharingStopped = onSharingStopped
        }

        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
            logger.error("CKShare save failed: \(error.localizedDescription, privacy: .public)")
            onSaveFailure(error)
        }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            controller.share?[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            onShareSaved(controller.share ?? share)
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            onSharingStopped()
        }
    }
}
#endif
