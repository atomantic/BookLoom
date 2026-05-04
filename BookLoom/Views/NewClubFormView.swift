import SwiftUI
import SwiftData

/// Sheet form for creating a new BookClub. Used both from the empty state and
/// from the "+ New Club" toolbar button on a non-empty clubs list.
struct NewClubFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MemberIdentity.self) private var memberIdentity

    @State private var name: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    BrandBadge(size: 44)
                    Text("New Club")
                        .font(.title3.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                    Spacer(minLength: 0)
                }
                .bookLoomCard(padding: 12)
                .frame(maxWidth: 460)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Club Name")
                        .font(.headline)
                        .foregroundStyle(BookLoomStyle.ink)
                    TextField("Tuesday Bookworms", text: $name)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .submitLabel(.done)
                        .onSubmit(createClub)

                    Label("Invite members from the club screen after it exists.", systemImage: "icloud.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .bookLoomCard(padding: 12)
                .frame(maxWidth: 460)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .bookLoomScreenBackground()
        .navigationTitle("New Club")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create", action: createClub)
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private var trimmedName: String { name.trimmed }

    private func createClub() {
        guard let name = name.trimmedOrNil else { return }
        let club = BookClub(name: name)
        let creatorID = memberIdentity.memberID
        if !creatorID.isEmpty {
            club.creatorMemberID = creatorID
            if let creatorName = memberIdentity.name.trimmedOrNil {
                var roster = club.knownMemberRoster
                roster[creatorID] = creatorName
                club.knownMemberRoster = roster
            }
        }
        context.insert(club)
        try? context.save()
        dismiss()
    }
}
