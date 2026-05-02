import SwiftUI

struct SettingsView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @State private var draftName: String = ""
    @State private var nameSaved: Bool = false

    var body: some View {
        Form {
            Section {
                TextField("Display name", text: $draftName)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                Button {
                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    memberIdentity.name = trimmed
                    nameSaved = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        nameSaved = false
                    }
                } label: {
                    if nameSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Save Name")
                    }
                }
                .disabled(
                    draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    draftName == memberIdentity.name
                )
            } header: {
                Text("Your Name")
            } footer: {
                Text("This is the name shown on your book submissions, ratings, and notes inside each club.")
            }

            Section {
                Label {
                    if Features.cloudKitSharing {
                        Text("Group sharing is enabled")
                    } else {
                        Text("Group sharing is in setup")
                    }
                } icon: {
                    Image(systemName: Features.cloudKitSharing ? "icloud.fill" : "icloud")
                        .foregroundStyle(Features.cloudKitSharing ? .blue : .secondary)
                }
                if !Features.cloudKitSharing {
                    Text("Once iCloud setup is complete, you'll be able to invite other members to a club. Until then, your data syncs across your own devices but cannot be shared.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("If sharing isn't working, check that you're signed into iCloud in Settings → [Your Name] and that iCloud Drive is on.")
            }

            Section("About") {
                LabeledContent("Version", value: appVersionString)
                LabeledContent("Build", value: appBuildString)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            draftName = memberIdentity.name
        }
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
