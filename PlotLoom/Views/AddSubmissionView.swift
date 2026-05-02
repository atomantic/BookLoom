import SwiftUI
import SwiftData

struct AddSubmissionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var club: BookClub

    @State private var title: String = ""
    @State private var author: String = ""
    @State private var isbn: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    BookCoverTile(title: title, author: author, width: 96, height: 132)
                    Text("Add a Proposal")
                        .font(.title.bold())
                        .foregroundStyle(PlotLoomStyle.ink)
                    Text(club.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        TextField("Title", text: $title)
                        TextField("Author", text: $author)
                        TextField("ISBN (optional)", text: $isbn)
                    }
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif

                    Button(action: addSubmission) {
                        Label("Add to Proposals", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedTitle.isEmpty)
                }
                .plotLoomCard(padding: 18)
                .frame(maxWidth: 500)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .plotLoomScreenBackground()
        .navigationTitle("Add Book")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var trimmedTitle: String { title.trimmed }

    private func addSubmission() {
        guard let title = title.trimmedOrNil else { return }
        let submission = BookSubmission(
            title: title,
            author: author.trimmed,
            isbn: isbn.trimmed,
            submittedBy: memberIdentity.name
        )
        submission.bookClub = club
        context.insert(submission)
        dismiss()
    }
}
