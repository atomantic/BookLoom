import SwiftUI

struct MemberOnboardingView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @State private var draftName: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                OnboardingHeroArtwork(maxHeight: 300)
                    .padding(.top, 12)

                VStack(spacing: 10) {
                    BrandBadge(size: 72)
                    Text("PlotLoom")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(PlotLoomStyle.ink)
                    Text("Make the next book feel chosen together.")
                        .font(.title3)
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
                        Label("Continue", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedName.isEmpty)
                }
                .plotLoomCard(padding: 18)
                .frame(maxWidth: 420)
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .plotLoomScreenBackground()
    }

    private var trimmedName: String { draftName.trimmed }

    private func saveName() {
        guard let name = draftName.trimmedOrNil else { return }
        memberIdentity.name = name
    }
}
