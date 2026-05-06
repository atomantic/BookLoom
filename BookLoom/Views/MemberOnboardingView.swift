import SwiftUI

struct MemberOnboardingView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @AppStorage(WelcomeReplay.storageKey) private var replayWelcome = false
    @State private var draftName: String = ""
    @State private var enableNotifications: Bool = true
    var isReplay: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OnboardingHeroArtwork(maxHeight: 210)
                    .padding(.top, 4)

                VStack(spacing: 6) {
                    Text("BookLoom")
                        .font(.largeTitle.weight(.semibold))
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

                    Toggle(isOn: $enableNotifications) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stay in the loop")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BookLoomStyle.ink)
                            Text("Get a notification when your clubs add proposals, pick a book, open a poll, schedule a meeting, or share new discussion. You can change this in Settings later.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button(action: saveName) {
                        Label(isReplay ? "Return to App" : "Continue", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(BookLoomProminentButtonStyle())
                    .controlSize(.large)
                    .bookLoomActionWidth()
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
        Task { @MainActor in
            await applyNotificationPreference()
            replayWelcome = false
        }
    }

    private func applyNotificationPreference() async {
        guard enableNotifications else {
            BookLoomNotificationPreferences.writeAll(enabled: false)
            return
        }
        let granted = await BookLoomUserNotifications.requestAuthorizationIfNeeded()
        BookLoomNotificationPreferences.writeAll(enabled: granted)
    }
}
