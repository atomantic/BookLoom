import Foundation
import CloudKit
import Observation
import SwiftData
import SwiftUI
import os

enum ShareAcceptanceState: Equatable {
    case idle
    case accepting
    case succeeded(clubName: String)
    case failed(message: String, retryable: Bool)
}

/// Serializes incoming share imports and keeps the active payload available
/// until it succeeds or the user explicitly dismisses it.
@MainActor
@Observable
final class ShareAcceptanceQueue<Payload> {
    typealias Operation = @MainActor (Payload) async throws -> String

    private struct PendingShare {
        let id: String
        let payload: Payload
    }

    private(set) var state: ShareAcceptanceState = .idle
    private(set) var pendingCount = 0

    private let identifier: (Payload) -> String
    private var operation: Operation?
    private var pending: [PendingShare] = []
    private var activeOperation: Task<Void, Never>?
    /// Retains the just-completed ID until its success alert is acknowledged,
    /// closing the callback race without blocking a later, legitimate rejoin.
    private var succeededID: String?

    init(identifier: @escaping (Payload) -> String) {
        self.identifier = identifier
    }

    func configure(operation: @escaping Operation) {
        self.operation = operation
        startIfPossible()
    }

    @discardableResult
    func enqueue(_ payload: Payload) -> Bool {
        let id = identifier(payload)
        guard succeededID != id, !pending.contains(where: { $0.id == id }) else {
            return false
        }

        pending.append(PendingShare(id: id, payload: payload))
        pendingCount = pending.count
        startIfPossible()
        return true
    }

    func retry() {
        guard case .failed = state else { return }
        state = .idle
        startIfPossible()
    }

    func dismiss() {
        switch state {
        case .failed:
            settleCurrent()
            state = .idle
            startIfPossible()
        case .succeeded:
            succeededID = nil
            state = .idle
            startIfPossible()
        case .idle, .accepting:
            break
        }
    }

    /// SwiftUI may update an alert binding before or after invoking its button
    /// action. Defer dismissal and only apply it if the action did not already
    /// move the queue to a new state.
    func dismissAlert(ifUnchangedFrom presentedState: ShareAcceptanceState) {
        guard state == presentedState else { return }
        dismiss()
    }

    /// Wait for the share currently being imported. App startup uses this
    /// before restoring already-accepted shared zones so both paths never
    /// mutate the same SwiftData context concurrently.
    func waitForActiveOperation() async {
        while let activeOperation {
            await activeOperation.value
        }
    }

    private func startIfPossible() {
        guard state == .idle,
              let operation,
              let current = pending.first else {
            return
        }

        state = .accepting
        activeOperation = Task { @MainActor [weak self] in
            defer { self?.activeOperation = nil }
            do {
                let clubName = try await operation(current.payload)
                guard let self, self.pending.first?.id == current.id else { return }
                self.succeededID = current.id
                self.removeCurrent()
                self.state = .succeeded(clubName: clubName)
            } catch {
                guard let self, self.pending.first?.id == current.id else { return }
                self.state = .failed(
                    message: ShareAcceptance.failureMessage(for: error),
                    retryable: ShareAcceptance.isRetryable(error)
                )
            }
        }
    }

    private func settleCurrent() {
        removeCurrent()
    }

    private func removeCurrent() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()
        pendingCount = pending.count
    }
}

/// Magic strings used when iOS/macOS deliver a CKShare invite via NSUserActivity.
/// These constants are NOT exposed by Apple's SDK — older sample code references
/// `CKShare.Metadata.activityType` which doesn't exist. Hardcode them.
enum ShareAcceptance {
    static let activityType = "com.apple.CloudKit.ShareMetadata"
    static let metadataKey = "CKShareMetadata"

    private static let logger = Logger(subsystem: "net.shadowpuppet.BookLoom", category: "ShareAccept")

    /// Extract metadata from a `NSUserActivity` payload (used by SwiftUI's
    /// `onContinueUserActivity` modifier).
    static func metadata(from activity: NSUserActivity) -> CKShare.Metadata? {
        activity.userInfo?[metadataKey] as? CKShare.Metadata
    }

    static func identifier(for metadata: CKShare.Metadata) -> String {
        let id = metadata.share.recordID
        return "\(id.zoneID.ownerName)|\(id.zoneID.zoneName)|\(id.recordName)"
    }

    static func failureMessage(for error: Error) -> String {
        if let sharingError = error as? SharingError {
            return sharingError.errorDescription ?? genericFailureMessage
        }

        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain else { return genericFailureMessage }
        switch nsError.code {
        case CKError.notAuthenticated.rawValue:
            return "Sign in to iCloud in Settings, then try joining the book club again."
        case CKError.accountTemporarilyUnavailable.rawValue:
            return "iCloud is temporarily unavailable. Check that iCloud Drive is enabled, then try again."
        case CKError.networkUnavailable.rawValue, CKError.networkFailure.rawValue:
            return "BookLoom couldn’t reach iCloud. Check your internet connection, then try again."
        case CKError.permissionFailure.rawValue:
            return "This invitation no longer grants access to the book club. Ask its owner for a new invitation."
        default:
            return genericFailureMessage
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        if let sharingError = error as? SharingError {
            switch sharingError {
            case .featureDisabled, .shareAccessRemoved:
                return false
            default:
                break
            }
        }
        let nsError = error as NSError
        return !(nsError.domain == CKErrorDomain && nsError.code == CKError.permissionFailure.rawValue)
    }

    private static let genericFailureMessage =
        "BookLoom couldn’t join this book club. Try again, or ask the club owner for a new invitation if the problem continues."

    /// Accept an incoming CKShare and insert a local `BookClub` row that
    /// represents the joined club. Idempotent — re-accepting the same share
    /// for an already-joined club won't duplicate the row.
    @MainActor
    static func handleAccept(
        metadata: CKShare.Metadata,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) async throws -> String {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        let info = try await CloudKitSharingService.shared.acceptShare(metadata: metadata)

        return try await importAcceptedShare(
            info,
            context: context,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
    }

    /// Rehydrates a share that CloudKit already accepted before the app was
    /// deleted or its local SwiftData store was rebuilt. This deliberately
    /// shares the import path with a new invitation so restoration remains
    /// idempotent and still passes every snapshot through authorization.
    @MainActor
    static func restoreAcceptedShare(
        _ info: AcceptedShareInfo,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) async throws -> String {
        guard Features.cloudKitSharing else {
            throw SharingError.featureDisabled
        }
        return try await importAcceptedShare(
            info,
            context: context,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
    }

    @MainActor
    private static func importAcceptedShare(
        _ info: AcceptedShareInfo,
        context: ModelContext,
        localMemberID: String,
        localMemberName: String
    ) async throws -> String {

        let zoneName = info.zoneName
        let descriptor = FetchDescriptor<BookClub>(
            predicate: #Predicate { $0.cloudZoneName == zoneName }
        )
        let existing = try context.fetch(descriptor)
        let joined: BookClub
        if let existingClub = existing.first {
            joined = existingClub
            logger.info("↺ Share accept matched existing zone \(info.zoneName, privacy: .public)")
        } else {
            joined = BookClub(name: info.title)
            joined.cloudZoneName = info.zoneName
            context.insert(joined)
        }

        joined.ownerUserRecordName = info.ownerUserRecordName
        joined.shareIsActive = true
        joined.shareParticipantCount = max(1, info.participantCount)
        let authorization = MemberSnapshotAuthorization.authorize(
            info.memberSnapshotBatch,
            existingBindings: joined.memberIdentityBindings,
            isShareOwner: false
        )
        joined.memberIdentityBindings = bindingsAfterAuthorization(
            existing: joined.memberIdentityBindings,
            authorization: authorization
        )

        if authorization.isTrustEstablished,
           authorization.rejectedRecordNames.isEmpty,
           !authorization.snapshots.isEmpty {
            try MemberShareSnapshotStore.merge(
                snapshots: authorization.snapshots,
                into: joined,
                context: context,
                localMemberID: localMemberID
            )
            try context.save()
            logger.info("✅ Accepted share — imported '\(joined.name, privacy: .public)' from \(authorization.snapshots.count) authenticated member snapshot(s)")
        } else {
            try context.save()
            logger.info("✅ Accepted share — joined '\(info.title, privacy: .public)' (zone \(info.zoneName, privacy: .public)); waiting for the first authenticated sync")
        }

        // Publish the joining member's empty snapshot so the owner gets
        // a push notification announcing the new participant and a
        // record they can fetch.
        SharedClubSync.publishIfNeeded(
            joined,
            context: context,
            localMemberID: localMemberID,
            localMemberName: localMemberName
        )
        return joined.name
    }

    /// A just-accepted share may not have materialized its owner record yet.
    /// Preserve a previously authenticated map on re-accept instead of replacing
    /// it with the fail-closed empty result from an inconclusive fetch.
    static func bindingsAfterAuthorization(
        existing: [String: String],
        authorization: MemberSnapshotAuthorizationResult
    ) -> [String: String] {
        authorization.isTrustEstablished ? authorization.bindings : existing
    }
}
