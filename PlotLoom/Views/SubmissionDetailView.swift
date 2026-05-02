import SwiftUI
import SwiftData

struct SubmissionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var submission: BookSubmission

    @State private var draftNote: String = ""

    var body: some View {
        Form {
            Section("Book") {
                LabeledContent("Title", value: submission.title)
                if !submission.author.isEmpty {
                    LabeledContent("Author", value: submission.author)
                }
                if !submission.isbn.isEmpty {
                    LabeledContent("ISBN", value: submission.isbn)
                }
                LabeledContent("Submitted by", value: submission.submittedBy)
                LabeledContent("Status", value: submission.status.displayName)
            }

            Section("Your Rating") {
                StarRatingView(stars: bindingForOwnRating())
            }

            Section("Group Ratings") {
                let allRatings = submission.ratings ?? []
                if allRatings.isEmpty {
                    Text("No ratings yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(allRatings) { rating in
                        HStack {
                            Text(rating.memberName)
                            Spacer()
                            Text(String(repeating: "★", count: rating.stars))
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }

            Section("Add Note") {
                TextField("Your thoughts…", text: $draftNote, axis: .vertical)
                    .lineLimit(3...8)
                Button("Save Note") {
                    let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let note = BookNote(memberName: memberIdentity.name, text: trimmed)
                    note.submission = submission
                    context.insert(note)
                    draftNote = ""
                }
                .disabled(draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Notes") {
                let allNotes = (submission.notes ?? []).sorted { $0.createdAt > $1.createdAt }
                if allNotes.isEmpty {
                    Text("No notes yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(allNotes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.memberName).font(.caption).foregroundStyle(.secondary)
                            Text(note.text)
                        }
                    }
                }
            }
        }
        .navigationTitle(submission.title)
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
}

private struct StarRatingView: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= stars ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
                    .onTapGesture { stars = (stars == i) ? 0 : i }
            }
        }
        .font(.title2)
    }
}
