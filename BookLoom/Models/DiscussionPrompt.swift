import Foundation
import SwiftData

enum DiscussionPromptSource: String, CaseIterable, Identifiable {
    case starter
    case custom

    var id: String { rawValue }
}

@Model
final class DiscussionPrompt {
    var question: String = ""
    var orderIndex: Int = 0
    var sourceRaw: String = DiscussionPromptSource.custom.rawValue
    var createdAt: Date = Date.now
    var isArchived: Bool = false

    var submission: BookSubmission? = nil

    init(
        question: String = "",
        orderIndex: Int = 0,
        source: DiscussionPromptSource = .custom,
        createdAt: Date = .now
    ) {
        self.question = question
        self.orderIndex = orderIndex
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
    }

    var source: DiscussionPromptSource {
        get { DiscussionPromptSource(rawValue: sourceRaw) ?? .custom }
        set { sourceRaw = newValue.rawValue }
    }
}
