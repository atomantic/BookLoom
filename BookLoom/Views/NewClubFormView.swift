import SwiftUI
import SwiftData

/// Sheet form for creating a new BookClub. Used both from the empty state and
/// from the "+ New Club" toolbar button on a non-empty clubs list.
struct NewClubFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MemberIdentity.self) private var memberIdentity

    let onCancel: (() -> Void)?
    let onCreated: ((BookClub) -> Void)?

    @State private var name: String = ""
    @State private var saveErrorMessage: String?

    init(
        onCancel: (() -> Void)? = nil,
        onCreated: ((BookClub) -> Void)? = nil
    ) {
        self.onCancel = onCancel
        self.onCreated = onCreated
    }

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
                Button("Cancel", action: cancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create", action: createClub)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .alert("Couldn't Create Club", isPresented: saveErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
    }

    private var trimmedName: String { name.trimmed }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
    }

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
        do {
            try context.save()
        } catch {
            // Remove only this failed insertion; rolling back the shared context
            // could discard unrelated edits that another view has not saved yet.
            context.delete(club)
            saveErrorMessage = "Your club wasn't created. Try again. If the problem continues, close and reopen BookLoom."
            return
        }
        if let onCreated {
            onCreated(club)
        } else {
            dismiss()
        }
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }
}
