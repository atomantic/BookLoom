import Foundation
import SwiftUI

/// Stores the local member's display name. Used to attribute submissions, ratings,
/// and notes within a shared book club. The CKShare layer (added later) handles
/// the actual identity/auth — this is just a friendly name for the UI.
@Observable
final class MemberIdentity {
    private static let defaultsKey = "net.shadowpuppet.PlotLoom.memberName"

    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Self.defaultsKey) }
    }

    var isConfigured: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        self.name = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
    }
}
