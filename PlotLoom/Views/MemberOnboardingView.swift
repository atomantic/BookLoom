import SwiftUI

struct MemberOnboardingView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @State private var draftName: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Welcome to PlotLoom")
                    .font(.largeTitle.bold())
                Text("Your book club's potluck pick.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your name").font(.subheadline).foregroundStyle(.secondary)
                TextField("e.g. Alex", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }

            Button("Continue") {
                memberIdentity.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(40)
    }
}
