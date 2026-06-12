import Foundation
import SwiftUI

/// Stores the local member's display name. Used to attribute submissions, ratings,
/// and notes within a shared book club. The CKShare layer (added later) handles
/// the actual identity/auth — this is just a friendly name for the UI.
///
/// The display name and member ID live in `UserDefaults`, not the Keychain. This
/// is an accepted low risk: the name is a non-secret UI label the user chooses
/// (already broadcast to every club participant via CloudKit), and the member ID
/// is a random per-device UUID with no credential value. Promote to the Keychain
/// only if either field ever becomes security-sensitive.
@Observable
final class MemberIdentity {
    private static let defaultsKey = "net.shadowpuppet.BookLoom.memberName"
    private static let idDefaultsKey = "net.shadowpuppet.BookLoom.memberID"
    private static let legacyDefaultsKey = "net.shadowpuppet.PlotLoom.memberName"
    private static let legacyIDDefaultsKey = "net.shadowpuppet.PlotLoom.memberID"

    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Self.defaultsKey) }
    }

    var memberID: String {
        didSet { UserDefaults.standard.set(memberID, forKey: Self.idDefaultsKey) }
    }

    var isConfigured: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        if AppLaunchOptions.isSampleDataEnabled {
            self.name = ScreenshotSampleData.memberName
            self.memberID = ScreenshotSampleData.memberID
            return
        }

        let defaults = UserDefaults.standard
        let resolvedName = defaults.string(forKey: Self.defaultsKey)
            ?? defaults.string(forKey: Self.legacyDefaultsKey)
            ?? ""
        if !resolvedName.isEmpty {
            defaults.set(resolvedName, forKey: Self.defaultsKey)
        }

        self.name = resolvedName
        if let existingID = defaults.string(forKey: Self.idDefaultsKey), !existingID.isEmpty {
            self.memberID = existingID
        } else if let legacyID = defaults.string(forKey: Self.legacyIDDefaultsKey), !legacyID.isEmpty {
            defaults.set(legacyID, forKey: Self.idDefaultsKey)
            self.memberID = legacyID
        } else {
            let generatedID = UUID().uuidString
            defaults.set(generatedID, forKey: Self.idDefaultsKey)
            self.memberID = generatedID
        }
    }
}
