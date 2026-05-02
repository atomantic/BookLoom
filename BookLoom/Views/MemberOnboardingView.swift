import SwiftUI

struct MemberOnboardingView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @AppStorage(WelcomeReplay.storageKey) private var replayWelcome = false
    @State private var draftName: String = ""
    var isReplay: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OnboardingHeroArtwork(maxHeight: 210)
                    .padding(.top, 4)

                VStack(spacing: 6) {
                    Text("BookLoom")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(BookLoomStyle.ink)
                    Text("Choose the next book together.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Enter your name now. Then create a club if you are starting one, or skip club creation and wait for an invite from an existing BookLoom club.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                OnboardingPrivacyNote()
                    .frame(maxWidth: 420)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Your Name")
                        .font(.headline)
                        .foregroundStyle(BookLoomStyle.ink)
                    TextField("Alex", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .submitLabel(.done)
                        .onSubmit(saveName)

                    Button(action: saveName) {
                        Label(isReplay ? "Return to App" : "Continue", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedName.isEmpty)
                }
                .bookLoomCard(padding: 12)
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .bookLoomScreenBackground()
        .onAppear {
            draftName = memberIdentity.name
        }
    }

    private var trimmedName: String { draftName.trimmed }

    private func saveName() {
        guard let name = draftName.trimmedOrNil else { return }
        memberIdentity.name = name
        replayWelcome = false
    }
}

private struct OnboardingPrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.icloud.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(BookLoomStyle.indigo)
                .symbolRenderingMode(.hierarchical)

            Text("BookLoom does not store club data on third-party servers. Clubs live in your private iCloud data or in shared iCloud data when a club owner invites members.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bookLoomCard(padding: 10)
    }
}
