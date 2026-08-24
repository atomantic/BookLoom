#if os(macOS)
import AppKit
import CloudKit
import SwiftUI

/// macOS counterpart to UICloudSharingController. Registering the CKShare on
/// an item provider gives the system share sheet ownership of recipient lookup
/// and participant creation without exposing a reusable public URL.
struct MacCloudSharingPickerView: NSViewRepresentable {
    let clubName: String
    let share: CKShare
    let container: CKContainer

    func makeCoordinator() -> Coordinator {
        Coordinator(share: share, container: container)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: "Invite Members Privately",
            target: context.coordinator,
            action: #selector(Coordinator.showSharingPicker(_:))
        )
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.image = NSImage(systemSymbolName: "person.2.badge.plus", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.share = share
        context.coordinator.container = container
    }

    @MainActor
    final class Coordinator: NSObject {
        var share: CKShare
        var container: CKContainer
        private var picker: NSSharingServicePicker?

        init(share: CKShare, container: CKContainer) {
            self.share = share
            self.container = container
        }

        @objc func showSharingPicker(_ sender: NSButton) {
            let options = CKAllowedSharingOptions(
                allowedParticipantPermissionOptions: .readWrite,
                allowedParticipantAccessOptions: .specifiedRecipientsOnly
            )
            let itemProvider = NSItemProvider()
            itemProvider.registerCKShare(
                share,
                container: container,
                allowedSharingOptions: options
            )
            let picker = NSSharingServicePicker(items: [itemProvider])
            self.picker = picker
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
#endif
