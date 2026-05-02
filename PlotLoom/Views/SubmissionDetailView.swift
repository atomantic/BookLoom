import SwiftUI
import SwiftData

struct SubmissionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var submission: BookSubmission

    @State private var draftNote: String = ""

    var body: some View {
        let summary = submission.ratingSummary
        let noteCount = (submission.notes ?? []).count

        List {
            Section {
                SubmissionHero(submission: submission)
                    .plotLoomListRow(top: 8, bottom: 12)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    InfoLine(label: "Title", value: submission.displayTitle)
                    if !submission.displayAuthor.isEmpty {
                        InfoLine(label: "Author", value: submission.displayAuthor)
                    }
                    if !submission.isbn.isEmpty {
                        InfoLine(label: "ISBN", value: submission.isbn)
                    }
                    InfoLine(label: "Submitted by", value: submission.displaySubmitter)
                }
                .plotLoomCard(padding: 16)
            } header: {
                SectionTitle(title: "Book")
            }
            .plotLoomListRow()

            Section {
                VStack(alignment: .leading, spacing: 16) {
                    StarRatingView(stars: bindingForOwnRating())
                    if summary.average != nil {
                        Label("\(summary.displayValue) average from \(summary.count) ratings", systemImage: "star.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No group ratings yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .plotLoomCard(padding: 16)
            } header: {
                SectionTitle(title: "Your Rating")
            }
            .plotLoomListRow()

            Section {
                let allRatings = (submission.ratings ?? []).sorted { $0.createdAt < $1.createdAt }
                if allRatings.isEmpty {
                    InlineEmptyState(
                        systemImage: "star",
                        title: "No Ratings",
                        message: "Ratings appear here as members weigh in."
                    )
                } else {
                    ForEach(allRatings) { rating in
                        HStack {
                            Text(rating.memberName)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(String(repeating: "★", count: rating.stars))
                                .foregroundStyle(PlotLoomStyle.gold)
                                .accessibilityLabel("\(rating.stars) stars")
                        }
                        .plotLoomCard(padding: 14, radius: 16)
                    }
                }
            } header: {
                SectionTitle(title: "Group Ratings", detail: "\(summary.count)")
            }
            .plotLoomListRow()

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Your thoughts...", text: $draftNote, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                    Button(action: saveNote) {
                        Label("Save Note", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftNote.trimmed.isEmpty)
                }
                .plotLoomCard(padding: 16)
            } header: {
                SectionTitle(title: "Add Note")
            }
            .plotLoomListRow()

            Section {
                let allNotes = (submission.notes ?? []).sorted { $0.createdAt > $1.createdAt }
                if allNotes.isEmpty {
                    InlineEmptyState(
                        systemImage: "note.text",
                        title: "No Notes",
                        message: "Capture favorite passages, objections, or meeting topics."
                    )
                } else {
                    ForEach(allNotes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(note.memberName, systemImage: "person.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(note.text)
                                .font(.body)
                                .foregroundStyle(PlotLoomStyle.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .plotLoomCard(padding: 14, radius: 16)
                    }
                }
            } header: {
                SectionTitle(title: "Notes", detail: "\(noteCount)")
            }
            .plotLoomListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .plotLoomScreenBackground()
        .navigationTitle(submission.displayTitle)
    }

    private func bindingForOwnRating() -> Binding<Int> {
        Binding(
            get: { ownRating()?.stars ?? 0 },
            set: { newValue in
                if let existing = ownRating() {
                    existing.stars = newValue
                } else {
                    let rating = Rating(memberName: memberIdentity.name, stars: newValue)
                    rating.submission = submission
                    context.insert(rating)
                }
            }
        )
    }

    private func ownRating() -> Rating? {
        (submission.ratings ?? []).first { $0.memberName == memberIdentity.name }
    }

    private func saveNote() {
        guard let trimmed = draftNote.trimmedOrNil else { return }
        let note = BookNote(memberName: memberIdentity.name, text: trimmed)
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

private struct SubmissionHero: View {
    @Bindable var submission: BookSubmission

    var body: some View {
        HStack(spacing: 18) {
            BookCoverTile(title: submission.displayTitle, author: submission.displayAuthor, width: 104, height: 144)
            VStack(alignment: .leading, spacing: 12) {
                StatusPill(status: submission.status)
                Text(submission.displayTitle)
                    .font(.title2.bold())
                    .foregroundStyle(PlotLoomStyle.ink)
                    .lineLimit(3)
                if !submission.displayAuthor.isEmpty {
                    Text(submission.displayAuthor)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .plotLoomCard(padding: 18)
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
