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
                    .bookLoomListRow(top: 6, bottom: 8)
            }

            Section {
                SettingsPreferencesCard(
                    draftName: $draftName,
                    appAppearanceRaw: $appAppearanceRaw,
                    replayWelcome: $replayWelcome,
                    nameSaved: nameSaved,
                    saveDisabled: saveDisabled,
                    onSaveName: saveName
                )
            } header: {
                SectionTitle(title: "Preferences")
            }
            .bookLoomListRow()

            Section {
                CloudKitStatusCard()
            } header: {
                SectionTitle(title: "Sync")
            }
            .bookLoomListRow()

            Section {
                VStack(spacing: 8) {
                    LabeledContent("Version", value: appVersionString)
                    LabeledContent("Build", value: appBuildString)
                }
                .font(.subheadline)
                .bookLoomCard(padding: 12)
            } header: {
                SectionTitle(title: "About")
            }
            .bookLoomListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
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
        HStack(spacing: 12) {
            BrandBadge(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Reader" : name)
                    .font(.headline.bold())
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(1)
                Text("Submissions, ratings, and notes use this name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 12)
    }
}

private struct SettingsPreferencesCard: View {
    @Binding var draftName: String
    @Binding var appAppearanceRaw: String
    @Binding var replayWelcome: Bool

    let nameSaved: Bool
    let saveDisabled: Bool
    let onSaveName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                HStack(spacing: 8) {
                    TextField("Display name", text: $draftName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .textFieldStyle(.roundedBorder)

                    Button(action: onSaveName) {
                        Label(
                            nameSaved ? "Saved" : "Save",
                            systemImage: nameSaved ? "checkmark.circle.fill" : "checkmark.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(nameSaved ? .green : nil)
                    .disabled(saveDisabled)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                Picker("Appearance", selection: $appAppearanceRaw) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            Button {
                replayWelcome = true
            } label: {
                Label("Relaunch Welcome", systemImage: "sparkles.rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .bookLoomCard(padding: 12)
    }
}

private struct CloudKitStatusCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(Features.cloudKitSharing ? "Group sharing is enabled" : "Group sharing is in setup")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
            } icon: {
                Image(systemName: Features.cloudKitSharing ? "icloud.fill" : "icloud")
                    .foregroundStyle(Features.cloudKitSharing ? BookLoomStyle.indigo : .secondary)
            }

            Text("If invites fail, confirm the device is signed into iCloud and iCloud Drive is on.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bookLoomCard(padding: 12)
    }
}
