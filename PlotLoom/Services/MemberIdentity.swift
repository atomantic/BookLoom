import Foundation
import SwiftUI

/// Stores the local member's display name. Used to attribute submissions, ratings,
/// and notes within a shared book club. The CKShare layer (added later) handles
/// the actual identity/auth — this is just a friendly name for the UI.
@Observable
final class MemberIdentity {
    private static let defaultsKey = "net.shadowpuppet.PlotLoom.memberName"
    private static let idDefaultsKey = "net.shadowpuppet.PlotLoom.memberID"

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

        self.name = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        if let existingID = UserDefaults.standard.string(forKey: Self.idDefaultsKey), !existingID.isEmpty {
            self.memberID = existingID
        } else {
            let generatedID = UUID().uuidString
            UserDefaults.standard.set(generatedID, forKey: Self.idDefaultsKey)
            self.memberID = generatedID
        }
    }
}
