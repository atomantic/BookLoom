import CloudKit
import XCTest
@testable import PlotLoom

final class InviteLoadErrorTests: XCTestCase {
    func test_mapsCloudKitAuthErrorsToActionableStates() {
        XCTAssertEqual(
            InviteLoadError.from(NSError(domain: CKErrorDomain, code: CKError.notAuthenticated.rawValue)),
            .notSignedIntoICloud
        )

        XCTAssertEqual(
            InviteLoadError.from(NSError(domain: CKErrorDomain, code: CKError.accountTemporarilyUnavailable.rawValue)),
            .iCloudDriveOff
        )
    }

    func test_mapsCloudKitNetworkErrors() {
        XCTAssertEqual(
            InviteLoadError.from(NSError(domain: CKErrorDomain, code: CKError.networkFailure.rawValue)),
            .networkUnavailable
        )
    }

    func test_usesMessageFallbacksForWrappedAuthErrors() {
        XCTAssertEqual(
            InviteLoadError.from(NSError(domain: "Wrapped", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Account temporarily unavailable due to bad or missing auth token"
            ])),
            .iCloudDriveOff
        )

        XCTAssertEqual(
            InviteLoadError.from(NSError(domain: "Wrapped", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "User is not signed in"
            ])),
            .notSignedIntoICloud
        )
    }

    func test_mapsProductionShareSchemaFailureToSetupState() {
        let recordID = CKRecord.ID(recordName: "Share-Test")
        let partialError = NSError(domain: CKErrorDomain, code: CKError.serverRejectedRequest.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Cannot create new type cloudkit.share in production schema"
        ])
        let error = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Error saving record",
            CKPartialErrorsByItemIDKey: [recordID: partialError]
        ])

        XCTAssertEqual(
            InviteLoadError.from(error),
            .productionSchemaMissing
        )
    }

    func test_otherErrorsExposeDiagnosticDomainCodeAndMessage() {
        let error = NSError(domain: "ExampleDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Specific failure"
        ])

        XCTAssertEqual(
            InviteLoadError.from(error),
            .other("ExampleDomain#42: Specific failure")
        )
    }
}
