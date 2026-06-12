import SwiftUI
import SwiftData
import CloudKit

/// The slice of `CloudKitSharingService` the invite flow depends on. Injecting
/// it lets previews/tests stub sharing without a provisioned CloudKit container.
@MainActor
protocol ClubSharingProviding {
    func createOrFetchShare(for club: BookClub, context: ModelContext, ownerMemberID: String, ownerName: String) async throws -> CKShare
    func cloudKitContainer() -> CKContainer
}

extension CloudKitSharingService: ClubSharingProviding {}

/// Sheet presented when the owner taps "Invite Members". Splits behavior
/// between iOS (native UICloudSharingController) and macOS (copy-link UX).
/// When `Features.cloudKitSharing` is off, shows a "coming soon" placeholder
/// and never touches CloudKit.
struct InviteView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MemberIdentity.self) private var memberIdentity
    @Bindable var club: BookClub

    private let sharingService: ClubSharingProviding

    @State private var share: CKShare? = nil
    @State private var loadError: InviteLoadError? = nil
    @State private var didCopyURL: Bool = false
    @State private var isLoading: Bool = false

    init(club: BookClub, sharingService: ClubSharingProviding = CloudKitSharingService.shared) {
        self.club = club
        self.sharingService = sharingService
    }

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
        } else if !club.isOwner {
            inviteLinkView
        } else if let loadError {
            errorView(loadError)
        } else if let share {
            shareView(share)
        } else {
            PreparingInviteView()
        }
    }

    @ViewBuilder
    private var inviteLinkView: some View {
        let canManage = club.isAdmin(memberID: memberIdentity.memberID)
        if let url = URL(string: club.inviteURLString), canManage {
            CopyInviteLinkView(
                clubName: club.name,
                url: url,
                didCopy: $didCopyURL
            )
        } else if canManage {
            InviteStatusView(
                systemImage: "link",
                title: "Invite link not available yet",
                message: "The creator hasn't published a shareable link yet. Once they open Invite Members in this club, the link appears here so you can invite others."
            )
        } else {
            InviteStatusView(
                systemImage: "lock.fill",
                title: "Invitations are creator + admin only",
                message: "Ask the club creator to promote you to admin if you'd like to invite new members."
            )
        }
    }

    private func errorView(_ error: InviteLoadError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: error.systemImage)
                .font(.system(size: 36))
                .foregroundStyle(error.tint)
            Text(error.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(error.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            if let hint = error.actionHint {
                Text(hint)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            Button {
                Task { await loadShare(force: true) }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BookLoomProminentButtonStyle())
            .controlSize(.large)
            .disabled(isLoading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bookLoomScreenBackground()
    }

    private var comingSoonView: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("Coming Soon")
                .font(.title2.bold())
            Text("Group sharing via iCloud is being set up. This invite flow will light up in a future build.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bookLoomScreenBackground()
    }

    @ViewBuilder
    private func shareView(_ share: CKShare) -> some View {
        #if os(iOS)
        CloudSharingControllerView(
            share: share,
            container: sharingService.cloudKitContainer()
        )
        .ignoresSafeArea()
        #else
        macShareView(share)
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private func macShareView(_ share: CKShare) -> some View {
        if let url = share.url {
            CopyInviteLinkView(clubName: club.name, url: url, didCopy: $didCopyURL)
                .frame(minWidth: 460, minHeight: 300)
        } else {
            InviteStatusView(
                systemImage: "person.2.badge.plus",
                title: "Share \"\(club.name)\"",
                message: "Share URL not yet available — try again in a moment."
            )
            .frame(minWidth: 460, minHeight: 300)
        }
    }
    #endif

    private func loadShare(force: Bool = false) async {
        guard Features.cloudKitSharing, club.isOwner else { return }
        guard force || share == nil else { return }
        isLoading = true
        loadError = nil
        if force {
            share = nil
        }
        defer { isLoading = false }
        do {
            let s = try await sharingService.createOrFetchShare(
                for: club,
                context: context,
                ownerMemberID: memberIdentity.memberID,
                ownerName: memberIdentity.name
            )
            try? context.save()
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
    case productionSchemaMissing
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
        let diagnostic = CloudKitErrorDescriber.describe(error)
        let message = diagnostic.lowercased()
        if message.contains(productionSchemaMarker) {
            return .productionSchemaMissing
        }
        if message.contains("auth token") || message.contains("temporarily unavailable") {
            return .iCloudDriveOff
        }
        if message.contains("not authenticated") || message.contains("not signed in") {
            return .notSignedIntoICloud
        }
        return .other(diagnostic)
    }

    static let productionSchemaMarker = "cannot create new type cloudkit.share in production schema"

    var systemImage: String {
        switch self {
        case .notSignedIntoICloud: return "icloud.slash"
        case .iCloudDriveOff: return "icloud.and.arrow.down"
        case .networkUnavailable: return "wifi.slash"
        case .productionSchemaMissing: return "icloud.and.arrow.up"
        case .other: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .productionSchemaMissing, .other: return BookLoomStyle.coral
        default: return BookLoomStyle.indigo
        }
    }

    var title: String {
        switch self {
        case .notSignedIntoICloud: return "Sign in to iCloud"
        case .iCloudDriveOff: return "Turn on iCloud Drive"
        case .networkUnavailable: return "No internet connection"
        case .productionSchemaMissing: return "CloudKit setup needed"
        case .other: return "Couldn't prepare invite"
        }
    }

    var body: String {
        switch self {
        case .notSignedIntoICloud:
            return "BookLoom needs an iCloud account to share clubs across devices and people."
        case .iCloudDriveOff:
            return "BookLoom uses iCloud to sync your book clubs, so iCloud Drive needs to be enabled."
        case .networkUnavailable:
            return "Connect to Wi-Fi or cellular and try again."
        case .productionSchemaMissing:
            return "The production CloudKit schema does not include iCloud sharing yet."
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
        case .productionSchemaMissing:
            return "Run a Development build once, create an invite, then deploy schema changes in CloudKit Console."
        case .networkUnavailable, .other:
            return nil
        }
    }
}

private struct CopyInviteLinkView: View {
    let clubName: String
    let url: URL
    @Binding var didCopy: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("Invite to \"\(clubName)\"")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(url.absoluteString)
                .font(.callout.monospaced())
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .bookLoomCard(padding: 12)
                .padding(.horizontal, 20)
            Button {
                Pasteboard.copy(url.absoluteString)
                didCopy = true
            } label: {
                Label(
                    didCopy ? "Copied!" : "Copy Invite Link",
                    systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.doc"
                )
            }
            .buttonStyle(BookLoomProminentButtonStyle())
            Text("Send this link via Messages, email, or any channel. The recipient must be signed into iCloud and have BookLoom installed. Only the club creator can revoke or re-issue links.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bookLoomScreenBackground()
    }
}

private struct InviteStatusView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bookLoomScreenBackground()
    }
}

enum Pasteboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

private struct PreparingInviteView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                Text("Preparing Invite")
                    .font(.title3.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                Text("Creating a private iCloud share for this club.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bookLoomScreenBackground()
    }
}
