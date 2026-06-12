import Foundation
import Observation
import SwiftData

/// Tracks the currently active book club. The whole app operates in the
/// context of this club: Books, Polls, Discussions, and Schedule tabs all
/// scope their content to whichever club is active here.
///
/// Persistence is the club's `cloudZoneName` (a stable per-club identifier
/// generated at creation), stored in UserDefaults so the app reopens to the
/// same club. Falls back to the most-recently-created visible club if the
/// stored ID can no longer be resolved (e.g. the club was deleted).
@Observable
@MainActor
final class ActiveClubStore {
    private static let defaultsKey = "net.shadowpuppet.BookLoom.activeClubZoneName"

    private(set) var activeClubZoneName: String?

    init() {
        self.activeClubZoneName = UserDefaults.standard.string(forKey: Self.defaultsKey)
    }

    /// Resolves the active club out of the supplied list without mutating
    /// state. If the stored ID no longer matches any club, returns the first
    /// visible club as a fallback so the app never lands in a "no club
    /// selected" state while clubs exist. Pure: safe to call from a SwiftUI
    /// `body`. Pair with `reconcileWithVisibleClubs(_:)` (in `.task` or
    /// `.onChange`) to persist the fallback selection.
    func resolveActiveClub(from clubs: [BookClub]) -> BookClub? {
        guard !clubs.isEmpty else { return nil }
        if let zoneName = activeClubZoneName,
           let match = clubs.first(where: { $0.cloudZoneName == zoneName }) {
            return match
        }
        return clubs.first
    }

    /// Side-effecting variant of `resolveActiveClub`. Persists the fallback
    /// selection so the next launch lands on the same club, and clears the
    /// stored ID when no clubs remain.
    func reconcileWithVisibleClubs(_ clubs: [BookClub]) {
        guard !clubs.isEmpty else {
            if activeClubZoneName != nil {
                clearActiveClub()
            }
            return
        }

        if let zoneName = activeClubZoneName,
           clubs.contains(where: { $0.cloudZoneName == zoneName }) {
            return
        }

        if let fallback = clubs.first {
            setActiveClub(fallback)
        }
    }

    func setActiveClub(_ club: BookClub) {
        activeClubZoneName = club.cloudZoneName
        UserDefaults.standard.set(club.cloudZoneName, forKey: Self.defaultsKey)
    }

    func clearActiveClub() {
        activeClubZoneName = nil
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }
}
