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
        Form {
            Section("Book") {
                TextField("Title", text: $title)
                TextField("Author", text: $author)
                TextField("ISBN (optional)", text: $isbn)
            }

            Section {
                Button("Add to Submissions") {
                    let submission = BookSubmission(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        author: author.trimmingCharacters(in: .whitespacesAndNewlines),
                        isbn: isbn.trimmingCharacters(in: .whitespacesAndNewlines),
                        submittedBy: memberIdentity.name
                    )
                    submission.bookClub = club
                    context.insert(submission)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Add Book")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
