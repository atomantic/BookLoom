import SwiftUI

struct SettingsView: View {
    @Environment(MemberIdentity.self) private var memberIdentity
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRaw = AppAppearance.system.rawValue
    @AppStorage(WelcomeReplay.storageKey) private var replayWelcome = false
    @State private var draftName: String = ""
    @State private var nameSaved: Bool = false

    var body: some View {
        List {
            Section {
                SettingsHeader(name: memberIdentity.name)
                    .plotLoomListRow(top: 8, bottom: 12)
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Display Name")
                        .font(.headline)
                        .foregroundStyle(PlotLoomStyle.ink)
                    TextField("Display name", text: $draftName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .textFieldStyle(.roundedBorder)

                    Button(action: saveName) {
                        Label(
                            nameSaved ? "Saved" : "Save Name",
                            systemImage: nameSaved ? "checkmark.circle.fill" : "checkmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(nameSaved ? .green : nil)
                    .disabled(saveDisabled)
                }
                .plotLoomCard(padding: 16)
            } header: {
                SectionTitle(title: "Profile")
            }
            .plotLoomListRow()

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Appearance")
                        .font(.headline)
                        .foregroundStyle(PlotLoomStyle.ink)
                    Picker("Appearance", selection: $appAppearanceRaw) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .plotLoomCard(padding: 16)
            } header: {
                SectionTitle(title: "Display")
            }
            .plotLoomListRow()

            Section {
                Button {
                    replayWelcome = true
                } label: {
                    Label("Relaunch Welcome", systemImage: "sparkles.rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .plotLoomCard(padding: 16)
            } header: {
                SectionTitle(title: "Welcome")
            }
            .plotLoomListRow()

            Section {
                CloudKitStatusCard()
            } header: {
                SectionTitle(title: "iCloud")
            }
            .plotLoomListRow()

            Section {
                VStack(spacing: 12) {
                    LabeledContent("Version", value: appVersionString)
                    LabeledContent("Build", value: appBuildString)
                }
                .plotLoomCard(padding: 16)
            } header: {
                SectionTitle(title: "About")
            }
            .plotLoomListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .plotLoomScreenBackground()
        .navigationTitle("Settings")
        .onAppear {
            draftName = memberIdentity.name
        }
    }

    private var saveDisabled: Bool {
        guard let trimmed = draftName.trimmedOrNil else { return true }
        return trimmed == memberIdentity.name
    }

    private func saveName() {
        guard let trimmed = draftName.trimmedOrNil else { return }
        memberIdentity.name = trimmed
        nameSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            nameSaved = false
        }
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var appBuildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }
}

private struct SettingsHeader: View {
    let name: String

    var body: some View {
        HStack(spacing: 14) {
            BrandBadge(size: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(name.isEmpty ? "Reader" : name)
                    .font(.title2.bold())
                    .foregroundStyle(PlotLoomStyle.ink)
                    .lineLimit(1)
                Text("Submissions, ratings, and notes use this name.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .plotLoomCard(padding: 18)
    }
}

private struct CloudKitStatusCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(Features.cloudKitSharing ? "Group sharing is enabled" : "Group sharing is in setup")
                    .font(.headline)
                    .foregroundStyle(PlotLoomStyle.ink)
            } icon: {
                Image(systemName: Features.cloudKitSharing ? "icloud.fill" : "icloud")
                    .foregroundStyle(Features.cloudKitSharing ? PlotLoomStyle.indigo : .secondary)
            }

            Text("If invites fail, confirm the device is signed into iCloud and iCloud Drive is on.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .plotLoomCard(padding: 16)
    }
}
