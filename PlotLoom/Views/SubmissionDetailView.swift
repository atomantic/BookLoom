import SwiftUI
import SwiftData

struct SubmissionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var submission: BookSubmission

    @State private var draftNote: String = ""
    @State private var draftPrompt: String = ""
    @State private var showingDiscussionMode: Bool = false

    var body: some View {
        let summary = submission.ratingSummary
        let noteCount = (submission.notes ?? []).count
        let allRatings = (submission.ratings ?? []).sorted { $0.createdAt < $1.createdAt }
        let allNotes = (submission.notes ?? []).sorted { $0.createdAt > $1.createdAt }
        let prompts = submission.activeDiscussionPrompts

        List {
            Section {
                SubmissionHero(submission: submission)
                    .plotLoomListRow(top: 6, bottom: 8)
            }

            Section {
                BookDetailsCard(submission: submission)
            } header: {
                SectionTitle(title: "Details")
            }
            .plotLoomListRow()

            Section {
                RatingsCard(stars: bindingForOwnRating(), summary: summary, ratings: allRatings)
            } header: {
                SectionTitle(title: "Ratings", detail: "\(summary.count)")
            }
            .plotLoomListRow()

            Section {
                NotesCard(draftNote: $draftNote, notes: allNotes, onSaveNote: saveNote)
            } header: {
                SectionTitle(title: "Notes", detail: "\(noteCount)")
            }
            .plotLoomListRow()

            Section {
                DiscussionPromptCard(
                    submission: submission,
                    draftPrompt: $draftPrompt,
                    onStartDiscussion: { showingDiscussionMode = true }
                )
            } header: {
                SectionTitle(title: "Discussion", detail: "\(prompts.count)")
            }
            .plotLoomListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .plotLoomScreenBackground()
        .navigationTitle(submission.displayTitle)
        .sheet(isPresented: $showingDiscussionMode) {
            DiscussionModeView(submissionTitle: submission.displayTitle, prompts: prompts)
        }
    }

    private func bindingForOwnRating() -> Binding<Int> {
        Binding(
            get: { ownRating()?.stars ?? 0 },
            set: { newValue in
                if let existing = ownRating() {
                    existing.stars = newValue
                } else {
                    let rating = Rating(memberID: memberIdentity.memberID, memberName: memberIdentity.name, stars: newValue)
                    rating.submission = submission
                    context.insert(rating)
                }
            }
        )
    }

    private func ownRating() -> Rating? {
        (submission.ratings ?? []).first { $0.matches(memberID: memberIdentity.memberID, memberName: memberIdentity.name) }
    }

    private func saveNote() {
        guard let trimmed = draftNote.trimmedOrNil else { return }
        let note = BookNote(memberID: memberIdentity.memberID, memberName: memberIdentity.name, text: trimmed)
        note.submission = submission
        context.insert(note)
        draftNote = ""
    }
}

private struct StarRatingView: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    stars = (stars == i) ? 0 : i
                } label: {
                    Image(systemName: i <= stars ? "star.fill" : "star")
                        .foregroundStyle(PlotLoomStyle.gold)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) stars")
            }
        }
        .font(.title2)
    }
}

private struct BookDetailsCard: View {
    let submission: BookSubmission

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !submission.isbn.isEmpty {
                InfoLine(label: "ISBN", value: submission.isbn)
            }
            if let publishedYear = submission.publishedYear {
                InfoLine(label: "Published", value: "\(publishedYear)")
            }
            InfoLine(label: "Submitted by", value: submission.displaySubmitter)

            if !submission.displayDescription.isEmpty {
                Divider()
                Text(submission.displayDescription)
                    .font(.callout)
                    .foregroundStyle(PlotLoomStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .plotLoomCard(padding: 12)
    }
}

private struct RatingsCard: View {
    @Binding var stars: Int

    let summary: RatingSummary
    let ratings: [Rating]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                StarRatingView(stars: $stars)
                Spacer(minLength: 12)
                if summary.average != nil {
                    Label(summary.displayValue, systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PlotLoomStyle.gold)
                }
            }

            if ratings.isEmpty {
                Text("No group ratings yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                VStack(spacing: 8) {
                    ForEach(ratings) { rating in
                        HStack {
                            Text(rating.memberName)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(String(repeating: "★", count: rating.stars))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PlotLoomStyle.gold)
                                .accessibilityLabel("\(rating.stars) stars")
                        }
                    }
                }
            }
        }
        .plotLoomCard(padding: 12)
    }
}

private struct NotesCard: View {
    @Binding var draftNote: String

    let notes: [BookNote]
    let onSaveNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Your thoughts...", text: $draftNote, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                Button(action: onSaveNote) {
                    Label("Save", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftNote.trimmed.isEmpty)
            }

            if notes.isEmpty {
                Text("Capture favorite passages, objections, or meeting topics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(note.memberName, systemImage: "person.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(note.text)
                                .font(.callout)
                                .foregroundStyle(PlotLoomStyle.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .plotLoomCard(padding: 12)
    }
}

private struct SubmissionHero: View {
    @Bindable var submission: BookSubmission

    var body: some View {
        HStack(spacing: 14) {
            BookCoverTile(
                title: submission.displayTitle,
                author: submission.displayAuthor,
                coverURL: submission.coverImageURL,
                width: 78,
                height: 108
            )
            VStack(alignment: .leading, spacing: 8) {
                StatusPill(status: submission.status)
                Text(submission.displayTitle)
                    .font(.title3.bold())
                    .foregroundStyle(PlotLoomStyle.ink)
                    .lineLimit(3)
                if !submission.displayAuthor.isEmpty {
                    Text(submission.displayAuthor)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .plotLoomCard(padding: 12)
    }
}

private struct InfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(PlotLoomStyle.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}
