import SwiftUI
import SwiftData

/// Club-level management page. Replaces the per-book-tab "Members" drill-down
/// so the Books tab can stay focused on books. Surfaces club-as-a-whole
/// concerns: editing the club name, member roster + admin status, sharing
/// invites, and deleting the club.
struct ClubManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MemberIdentity.self) private var memberIdentity
    @Environment(ActiveClubStore.self) private var activeClubStore
    @Bindable var club: BookClub

    @State private var draftName: String = ""
    @State private var nameSaved: Bool = false
    @State private var showingInvite = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        let members = club.memberDigests
        let unnamedCount = max(0, club.displayedMemberCount - members.count)
        let canManageAdmins = club.isOwner

        List {
            Section {
                ClubInfoCard(
                    club: club,
                    draftName: $draftName,
                    nameSaved: nameSaved,
                    canEditName: club.isOwner,
                    saveDisabled: nameSaveDisabled,
                    onSaveName: saveName
                )
            } header: {
                SectionTitle(title: "Club")
            }
            .bookLoomListRow()

            Section {
                if members.isEmpty && unnamedCount == 0 {
                    InlineEmptyState(
                        systemImage: "person.2.fill",
                        title: "No Members Yet",
                        message: "Accepted members appear here as the club syncs."
                    )
                } else {
                    ForEach(members) { member in
                        ClubMemberRow(
                            member: member,
                            isCreator: isCreator(member),
                            isAdmin: club.isAdmin(memberID: member.id),
                            canToggleAdmin: canToggleAdmin(for: member, canManage: canManageAdmins),
                            adminToggle: { newValue in
                                toggleAdmin(memberID: member.id, isAdmin: newValue)
                            }
                        )
                    }

                    ForEach(0..<unnamedCount, id: \.self) { _ in
                        UnnamedMemberRow()
                    }
                }
            } header: {
                SectionTitle(title: "Members", detail: "\(club.displayedMemberCount)")
            }
            .bookLoomListRow()

            Section {
                if club.isOwner {
                    Button {
                        showingInvite = true
                    } label: {
                        Label("Manage Sharing", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    PermissionsHelpRow(
                        message: "Toggle admin to grant a member the same management abilities you have. The club creator is always admin and cannot be demoted."
                    )
                } else {
                    PermissionsHelpRow(
                        message: localUserIsAdmin
                            ? "You're an admin. Only the club creator can change other members' admin status."
                            : "The creator manages invitations and admin permissions."
                    )
                }
            } header: {
                SectionTitle(title: "Permissions")
            }
            .bookLoomListRow()

            Section {
                ClubDeleteCard(
                    club: club,
                    isDeleting: isDeleting,
                    onTapDelete: { showingDeleteConfirmation = true }
                )
            } header: {
                SectionTitle(title: club.isOwner ? "Delete Club" : "Leave Club")
            }
            .bookLoomListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Manage Club")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingInvite) {
            InviteView(club: club)
        }
        .confirmationDialog(
            club.isOwner ? "Delete \(club.name)?" : "Leave \(club.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(club.isOwner ? "Delete Club" : "Leave Club", role: .destructive) {
                deleteClub()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if club.isOwner {
                Text("This removes the club and its proposals, meetings, votes, ratings, and notes from this device, and from anyone you've shared it with.")
            } else {
                Text("This removes the club from this device. The owner's copy is unaffected.")
            }
        }
        .onAppear {
            draftName = club.name
        }
        .task {
            backfillCreatorIfNeeded()
        }
    }

    private var localUserIsAdmin: Bool {
        club.isAdmin(memberID: memberIdentity.memberID)
    }

    private var nameSaveDisabled: Bool {
        guard club.isOwner else { return true }
        guard let trimmed = draftName.trimmedOrNil else { return true }
        return trimmed == club.name
    }

    private func isCreator(_ member: ClubMemberDigest) -> Bool {
        !club.creatorMemberID.isEmpty && member.id == club.creatorMemberID
    }

    private func canToggleAdmin(for member: ClubMemberDigest, canManage: Bool) -> Bool {
        guard canManage else { return false }
        // Synthetic name-keyed entries (no real memberID) can't be tracked
        // across devices, so admin status would never sync.
        guard !member.id.hasPrefix("name:") else { return false }
        if member.id == club.creatorMemberID { return false }
        return true
    }

    private func toggleAdmin(memberID: String, isAdmin: Bool) {
        club.setAdmin(isAdmin, memberID: memberID)
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        } catch {
            assertionFailure("Failed to update admin set: \(error.localizedDescription)")
        }
    }

    private func saveName() {
        guard club.isOwner, let trimmed = draftName.trimmedOrNil, trimmed != club.name else { return }
        club.name = trimmed
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
            nameSaved = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { nameSaved = false }
            }
        } catch {
            assertionFailure("Failed to rename club: \(error.localizedDescription)")
        }
    }

    private func deleteClub() {
        guard !isDeleting else { return }
        isDeleting = true
        let memberID = memberIdentity.memberID
        let zoneName = club.cloudZoneName
        let isActive = zoneName == activeClubStore.activeClubZoneName
        Task { @MainActor in
            await SharedClubSync.cleanupBeforeDelete(club, localMemberID: memberID)
            context.delete(club)
            try? context.save()
            if isActive {
                activeClubStore.clearActiveClub()
            }
            isDeleting = false
            dismiss()
        }
    }

    /// Backfill the creator on legacy clubs where the field was never set.
    /// Safe because only the local CKShare owner can have created the club.
    private func backfillCreatorIfNeeded() {
        guard club.creatorMemberID.isEmpty,
              club.isOwner,
              !memberIdentity.memberID.isEmpty
        else { return }
        club.creatorMemberID = memberIdentity.memberID
        try? context.save()
    }
}

private struct ClubInfoCard: View {
    @Bindable var club: BookClub
    @Binding var draftName: String
    let nameSaved: Bool
    let canEditName: Bool
    let saveDisabled: Bool
    let onSaveName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BrandBadge(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(club.name)
                        .font(.headline.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                        .lineLimit(1)
                    Label(sharing.label, systemImage: sharing.icon)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if canEditName {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Club Name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BookLoomStyle.ink)
                    HStack(spacing: 8) {
                        TextField("Club name", text: $draftName)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit(onSaveName)

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
            } else {
                Text("Only the club creator can rename the club.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .bookLoomCard(padding: 12)
    }

    private var sharing: (label: String, icon: String) {
        if !club.isOwner {
            return ("Shared with you", "person.2.fill")
        }
        return club.shareIsActive
            ? ("Sharing enabled", "icloud.fill")
            : ("Owner only", "person.crop.circle.fill")
    }
}

private struct ClubDeleteCard: View {
    let club: BookClub
    let isDeleting: Bool
    let onTapDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive, action: onTapDelete) {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(buttonTitle, systemImage: "trash.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeleting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bookLoomCard(padding: 12)
    }

    private var buttonTitle: String {
        if isDeleting {
            return club.isOwner ? "Deleting…" : "Leaving…"
        }
        return club.isOwner ? "Delete Club" : "Leave Club"
    }

    private var message: String {
        club.isOwner
            ? "Permanently removes this club from this device and from anyone you've shared it with. This can't be undone."
            : "Removes the club from this device. The owner's copy is unaffected."
    }
}

private struct ClubMemberRow: View {
    let member: ClubMemberDigest
    let isCreator: Bool
    let isAdmin: Bool
    let canToggleAdmin: Bool
    let adminToggle: @MainActor (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCreator ? "crown.fill" : "person.crop.circle.fill")
                .font(.title3)
                .foregroundStyle(isCreator ? BookLoomStyle.gold : BookLoomStyle.indigo)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(1)
                Text(activityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            roleControl
        }
        .bookLoomCard(padding: 10)
    }

    @ViewBuilder
    private var roleControl: some View {
        if isCreator {
            TintedCapsuleLabel(
                text: "Creator",
                tint: BookLoomStyle.gold,
                systemImage: "crown.fill"
            )
        } else if canToggleAdmin {
            Toggle(
                "Admin",
                isOn: Binding(
                    get: { isAdmin },
                    set: { newValue in adminToggle(newValue) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(BookLoomStyle.indigo)
        } else if isAdmin {
            TintedCapsuleLabel(
                text: "Admin",
                tint: BookLoomStyle.indigo,
                systemImage: "checkmark.shield.fill"
            )
        } else {
            EmptyView()
        }
    }

    private var activityLabel: String {
        switch member.activityCount {
        case 0: return "Joined"
        case 1: return "1 club activity"
        default: return "\(member.activityCount) club activities"
        }
    }
}

private struct UnnamedMemberRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("Accepted Member")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                Text("Name appears after club activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 10)
    }
}

private struct PermissionsHelpRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(BookLoomStyle.plum)
                .frame(width: 28)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .bookLoomCard(padding: 10)
    }
}
