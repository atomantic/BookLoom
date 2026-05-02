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
    @State private var loadError: InviteLoadError? = nil
    @State private var didCopyURL: Bool = false
    @State private var isLoading: Bool = false

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
            PreparingInviteView()
        }
    }

    private func errorView(_ error: InviteLoadError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: error.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(error.tint)
            Text(error.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(error.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            if let hint = error.actionHint {
                Text(hint)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }
            Button {
                Task { await loadShare(force: true) }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .plotLoomScreenBackground()
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
        .plotLoomScreenBackground()
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
        .plotLoomScreenBackground()
    }
    #endif

    private func loadShare(force: Bool = false) async {
        guard Features.cloudKitSharing else { return }
        guard force || share == nil else { return }
        isLoading = true
        loadError = nil
        if force {
            share = nil
        }
        defer { isLoading = false }
        do {
            let s = try await CloudKitSharingService.shared.createOrFetchShare(for: club)
            self.share = s
        } catch {
            self.loadError = InviteLoadError.from(error)
        }
    }
}

/// Categorized error states for the invite flow. Each case produces user-actionable
/// copy explaining what to do — never raw `localizedDescription` strings, since the
/// CKError messages ("Account temporarily unavailable due to bad or missing auth token")
/// are useless to a non-developer.
enum InviteLoadError: Equatable {
    case notSignedIntoICloud
    case iCloudDriveOff
    case networkUnavailable
    case other(String)

    static func from(_ error: Error) -> InviteLoadError {
        // CKError surfaces are wrapped in NSError; bridge to inspect the code.
        let ns = error as NSError
        if ns.domain == CKErrorDomain {
            switch ns.code {
            case CKError.notAuthenticated.rawValue:
                return .notSignedIntoICloud
            case CKError.accountTemporarilyUnavailable.rawValue:
                return .iCloudDriveOff
            case CKError.networkUnavailable.rawValue, CKError.networkFailure.rawValue:
                return .networkUnavailable
            default:
                break
            }
        }
        // Heuristic fallback: the wording "auth token" / "temporarily unavailable"
        // shows up in messages even when the code path doesn't expose CKErrorDomain.
        let message = ns.localizedDescription.lowercased()
        if message.contains("auth token") || message.contains("temporarily unavailable") {
            return .iCloudDriveOff
        }
        if message.contains("not authenticated") || message.contains("not signed in") {
            return .notSignedIntoICloud
        }
        return .other(error.localizedDescription)
    }

    var systemImage: String {
        switch self {
        case .notSignedIntoICloud: return "icloud.slash"
        case .iCloudDriveOff: return "icloud.and.arrow.down"
        case .networkUnavailable: return "wifi.slash"
        case .other: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .other: return .orange
        default: return .blue
        }
    }

    var title: String {
        switch self {
        case .notSignedIntoICloud: return "Sign in to iCloud"
        case .iCloudDriveOff: return "Turn on iCloud Drive"
        case .networkUnavailable: return "No internet connection"
        case .other: return "Couldn't prepare invite"
        }
    }

    var body: String {
        switch self {
        case .notSignedIntoICloud:
            return "PlotLoom needs an iCloud account to share clubs across devices and people."
        case .iCloudDriveOff:
            return "PlotLoom uses iCloud to sync your book clubs, so iCloud Drive needs to be enabled."
        case .networkUnavailable:
            return "Connect to Wi-Fi or cellular and try again."
        case .other(let detail):
            return detail
        }
    }

    var actionHint: String? {
        switch self {
        case .notSignedIntoICloud:
            return "Open Settings → tap \"Sign in to your iPhone\" at the top, then come back."
        case .iCloudDriveOff:
            return "Open Settings → [Your Name] → iCloud → turn on iCloud Drive, then come back."
        case .networkUnavailable, .other:
            return nil
        }
    }
}

private struct PreparingInviteView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                Text("Preparing Invite")
                    .font(.title3.bold())
                    .foregroundStyle(PlotLoomStyle.ink)
                Text("Creating a private iCloud share for this club.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .plotLoomScreenBackground()
    }
}
