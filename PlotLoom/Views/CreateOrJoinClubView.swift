import SwiftUI
import SwiftData

struct CreateOrJoinClubView: View {
    @Environment(\.modelContext) private var context
    @State private var clubName: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Start your book club")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Club name").font(.subheadline).foregroundStyle(.secondary)
                TextField("e.g. Tuesday Bookworms", text: $clubName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }

            Button("Create Club") {
                let trimmed = clubName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let club = BookClub(name: trimmed)
                context.insert(club)
            }
            .buttonStyle(.borderedProminent)
            .disabled(clubName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text("Joining a club via iCloud invite link will be added in a later update.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
        .padding(40)
    }
}
