import SwiftUI

struct MemberOnboardingView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @AppStorage(WelcomeReplay.storageKey) private var replayWelcome = false
    @State private var draftName: String = ""
    var isReplay: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                OnboardingHeroArtwork(maxHeight: 245)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("PlotLoom")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(PlotLoomStyle.ink)
                    Text("Choose the next book together.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Your Name")
                        .font(.headline)
                        .foregroundStyle(PlotLoomStyle.ink)
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
                .plotLoomCard(padding: 18)
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .plotLoomScreenBackground()
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
