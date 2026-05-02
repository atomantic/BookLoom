import SwiftUI
import SwiftData

/// Sheet form for creating a new BookClub. Used both from the empty state and
/// from the "+ New Club" toolbar button on a non-empty clubs list.
struct NewClubFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    BrandBadge(size: 58)
                    Text("New Club")
                        .font(.title.bold())
                        .foregroundStyle(PlotLoomStyle.ink)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Club Name")
                        .font(.headline)
                        .foregroundStyle(PlotLoomStyle.ink)
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
                .plotLoomCard(padding: 18)
                .frame(maxWidth: 460)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .plotLoomScreenBackground()
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
        context.insert(club)
        dismiss()
    }
}
