import SwiftData
import SwiftUI

struct DiscussionPromptCard: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var submission: BookSubmission
    @Binding var draftPrompt: String
    let onStartDiscussion: () -> Void

    var body: some View {
        let prompts = submission.activeDiscussionPrompts

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Add a discussion question", text: $draftPrompt, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button(action: addPrompt) {
                    Label("Add", systemImage: "plus.circle")
                }
                .buttonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.indigo))
                .disabled(draftPrompt.trimmed.isEmpty)
            }

            if prompts.isEmpty {
                Button {
                    DiscussionPromptLibrary.ensureStarterPrompts(for: submission, context: context)
                    saveDiscussionChanges()
                } label: {
                    Label("Add Starter Prompts", systemImage: "text.bubble")
                }
                .buttonStyle(BookLoomProminentButtonStyle())
                .bookLoomActionWidth()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(prompts) { prompt in
                        Text(prompt.question)
                            .font(.callout)
                            .foregroundStyle(BookLoomStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .bookLoomCardSurface()
                    }
                }

                Button(action: onStartDiscussion) {
                    Label("Discussion Mode", systemImage: "rectangle.on.rectangle.angled")
                }
                .buttonStyle(BookLoomProminentButtonStyle())
                .bookLoomActionWidth()
            }
        }
        .bookLoomCard(padding: 12)
    }

    private func addPrompt() {
        guard let question = draftPrompt.trimmedOrNil else { return }
        var prompts = submission.discussionPrompts ?? []
        let prompt = DiscussionPrompt(
            question: question,
            orderIndex: prompts.count,
            source: .custom
        )
        prompt.submission = submission
        prompt.createdByMemberID = memberIdentity.memberID
        context.insert(prompt)
        prompts.append(prompt)
        submission.discussionPrompts = prompts
        draftPrompt = ""
        saveDiscussionChanges()
    }

    private func saveDiscussionChanges() {
        do {
            try context.saveAndPublishIfNeeded(club: submission.bookClub, memberIdentity: memberIdentity)
        } catch {
            assertionFailure("Failed to save discussion changes: \(error.localizedDescription)")
        }
    }
}

struct DiscussionModeView: View {
    let submissionTitle: String
    let prompts: [DiscussionPrompt]

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 12)
                Text("Question \(min(index + 1, prompts.count)) of \(prompts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(prompts[safe: index]?.question ?? "No prompts yet.")
                    .font(.title2.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(24)
                    .frame(maxWidth: 620)
                    .bookLoomCardSurface()
                Spacer(minLength: 12)
                HStack {
                    Button {
                        index = max(index - 1, 0)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(index == 0)

                    Spacer()

                    Button {
                        index = min(index + 1, max(prompts.count - 1, 0))
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(index >= prompts.count - 1)
                }
                .buttonStyle(BookLoomProminentButtonStyle())
                .frame(maxWidth: 620)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .bookLoomScreenBackground()
            .navigationTitle(submissionTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
