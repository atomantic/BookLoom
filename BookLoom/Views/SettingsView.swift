import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRaw = AppAppearance.system.rawValue
    @AppStorage(WelcomeReplay.storageKey) private var replayWelcome = false
    @AppStorage(BookLoomNotificationPreferences.proposalKey) private var proposalNotifications = true
    @AppStorage(BookLoomNotificationPreferences.selectionKey) private var selectionNotifications = true
    @AppStorage(BookLoomNotificationPreferences.discussionKey) private var discussionNotifications = true
    @State private var draftName: String = ""
    @State private var nameSaved: Bool = false
    @State private var showingResetConfirmation: Bool = false
    @State private var isResetting: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeader(name: memberIdentity.name)
                    .frame(maxWidth: .infinity)

                SettingsSection("Preferences") {
                    SettingsPreferencesCard(
                        draftName: $draftName,
                        appAppearanceRaw: $appAppearanceRaw,
                        nameSaved: nameSaved,
                        saveDisabled: saveDisabled,
                        onSaveName: saveName
                    )
                }

                SettingsSection("Notifications") {
                    NotificationPreferencesCard(
                        proposalNotifications: $proposalNotifications,
                        selectionNotifications: $selectionNotifications,
                        discussionNotifications: $discussionNotifications
                    )
                }

                SettingsSection("Sync") {
                    CloudKitStatusCard()
                }

                SettingsSection("Data") {
                    DataResetCard(
                        isResetting: isResetting,
                        onTapReset: { showingResetConfirmation = true }
                    )
                }

                SettingsSection("Welcome") {
                    RelaunchWelcomeCard(replayWelcome: $replayWelcome)
                }

                SettingsSection("About") {
                    VStack(spacing: 8) {
                        LabeledContent("Version", value: appVersionString)
                        LabeledContent("Build", value: appBuildString)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .bookLoomCard(padding: 12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .bookLoomScreenBackground()
        .navigationTitle("Settings")
        .bookLoomNavigationBar()
        .confirmationDialog(
            "Delete all your BookLoom data?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                runReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every club, proposal, rating, note, meeting, and poll on this device. Owned clubs are deleted from iCloud; clubs you joined are left. This can't be undone.")
        }
        .onAppear {
            draftName = memberIdentity.name
        }
        .onChange(of: proposalNotifications) { _, enabled in
            requestNotificationAuthorizationIfNeeded(enabled: enabled) {
                proposalNotifications = false
            }
        }
        .onChange(of: selectionNotifications) { _, enabled in
            requestNotificationAuthorizationIfNeeded(enabled: enabled) {
                selectionNotifications = false
            }
        }
        .onChange(of: discussionNotifications) { _, enabled in
            requestNotificationAuthorizationIfNeeded(enabled: enabled) {
                discussionNotifications = false
            }
        }
    }

    private var saveDisabled: Bool {
        guard let trimmed = draftName.trimmedOrNil else { return true }
        return trimmed == memberIdentity.name
    }

    private func runReset() {
        guard !isResetting else { return }
        isResetting = true
        Task { @MainActor in
            await BookLoomDataReset.resetAllData(context: context, memberIdentity: memberIdentity)
            draftName = ""
            replayWelcome = true
            isResetting = false
        }
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

    private func requestNotificationAuthorizationIfNeeded(enabled: Bool, onDenied: @escaping () -> Void) {
        guard enabled else { return }
        Task {
            let granted = await BookLoomUserNotifications.requestAuthorizationIfNeeded()
            if !granted {
                await MainActor.run {
                    onDenied()
                }
            }
        }
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var appBuildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: title)
            content
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .bookLoomCard(padding: 12)
    }
}

private struct SettingsPreferencesCard: View {
    @Binding var draftName: String
    @Binding var appAppearanceRaw: String

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
                .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bookLoomCard(padding: 12)
    }
}

private struct RelaunchWelcomeCard: View {
    @Binding var replayWelcome: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Replay the welcome flow to revisit setup steps and tips.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                replayWelcome = true
            } label: {
                Label("Relaunch Welcome", systemImage: "sparkles.rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bookLoomCard(padding: 12)
    }
}

private struct NotificationPreferencesCard: View {
    @Binding var proposalNotifications: Bool
    @Binding var selectionNotifications: Bool
    @Binding var discussionNotifications: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $proposalNotifications) {
                Label("Book proposals", systemImage: "plus.circle")
            }
            Toggle(isOn: $selectionNotifications) {
                Label("Picks and polls", systemImage: "book.closed")
            }
            Toggle(isOn: $discussionNotifications) {
                Label("Discussion, prompts, and meetings", systemImage: "text.bubble")
            }

            Text("Notifications are sent from this device after BookLoom receives shared iCloud updates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bookLoomCard(padding: 12)
    }
}

private struct DataResetCard: View {
    let isResetting: Bool
    let onTapReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delete all of your local clubs and remove the matching iCloud data. The app returns to first-launch state.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive, action: onTapReset) {
                HStack(spacing: 8) {
                    if isResetting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(isResetting ? "Resetting…" : "Delete All My Data", systemImage: "trash.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isResetting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .bookLoomCard(padding: 12)
    }
}
