import Foundation

/// Picks a random proposed submission to become the next "current" read.
/// Pulled out as a free function so it's trivially testable without a ModelContext.
enum BookPicker {
    static func pickNext(from proposed: [BookSubmission]) -> BookSubmission? {
        var generator = SystemRandomNumberGenerator()
        return pickNext(from: proposed, using: &generator)
    }

    static func pickNext<R: RandomNumberGenerator>(from proposed: [BookSubmission], using generator: inout R) -> BookSubmission? {
        reducedProposalPool(from: proposed, using: &generator)
            .randomElement(using: &generator)
    }

    static func reducedProposalPool<R: RandomNumberGenerator>(from proposed: [BookSubmission], using generator: inout R) -> [BookSubmission] {
        let proposedByMember = Dictionary(
            grouping: proposed.filter { $0.status == .proposed },
            by: proposerKey
        )

        return proposedByMember.keys.sorted().compactMap { key in
            proposedByMember[key]?.randomElement(using: &generator)
        }
    }

    private static func proposerKey(for submission: BookSubmission) -> String {
        if let memberID = submission.submittedByMemberID.trimmedOrNil {
            return "id:\(memberID)"
        }
        if let name = submission.submittedBy.trimmedOrNil {
            return "name:\(name.lowercased())"
        }
        return "submission:\(submission.selectionID)"
    }
}
