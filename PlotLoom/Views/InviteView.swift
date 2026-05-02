import SwiftUI
import SwiftData
import CloudKit

/// Sheet presented when the owner taps "Invite Members". Splits behavior
/// between iOS (native UICloudSharingController) and macOS (copy-link UX).
/// When `Features.cloudKitSharing` is off, shows a "coming soon" placeholder
/// and never touches CloudKit.
struct InviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var club: BookClub

    @State private var share: CKShare? = nil
    @State private var loadError: String? = nil
    @State private var didCopyURL: Bool = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Invite Members")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task { await loadShare() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !Features.cloudKitSharing {
            comingSoonView
        } else if let loadError {
            errorView(loadError)
        } else if let share {
            shareView(share)
        } else {
            ProgressView("Preparing share…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var comingSoonView: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Coming Soon")
                .font(.title2.bold())
            Text("Group sharing via iCloud is being set up. This invite flow will light up in a future build.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Couldn't prepare invite")
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func shareView(_ share: CKShare) -> some View {
        #if os(iOS)
        CloudSharingControllerView(
            share: share,
            container: CloudKitSharingService.shared.cloudKitContainer()
        )
        .ignoresSafeArea()
        #else
        macShareView(share)
        #endif
    }

    #if os(macOS)
    private func macShareView(_ share: CKShare) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Share \"\(club.name)\"")
                .font(.title2.bold())
            if let url = share.url {
                Text(url.absoluteString)
                    .font(.callout.monospaced())
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 32)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    didCopyURL = true
                } label: {
                    Label(didCopyURL ? "Copied!" : "Copy Invite Link",
                          systemImage: didCopyURL ? "checkmark.circle.fill" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Share URL not yet available — try again in a moment.")
                    .foregroundStyle(.secondary)
            }
            Text("Send this link via Messages, email, or any channel. The recipient must be signed into iCloud and have PlotLoom installed.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
    }
    #endif

    private func loadShare() async {
        guard Features.cloudKitSharing else { return }
        guard share == nil else { return }
        do {
            let s = try await CloudKitSharingService.shared.createOrFetchShare(for: club)
            self.share = s
        } catch {
            self.loadError = error.localizedDescription
        }
    }
}
