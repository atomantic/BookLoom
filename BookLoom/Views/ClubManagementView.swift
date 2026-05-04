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
    @State private var memberPendingRemoval: ClubMemberDigest? = nil

    var body: some View {
        let members = club.memberDigests
        let unnamedCount = max(0, club.displayedMemberCount - members.count)
        let localID = memberIdentity.memberID
        let canManageClub = club.isAdmin(memberID: localID)
        let canDelete = club.isCreator(memberID: localID)
        let canManageAdmins = canDelete

        List {
            Section {
                ClubInfoCard(
                    club: club,
                    draftName: $draftName,
                    nameSaved: nameSaved,
                    canEditName: canManageClub,
                    saveDisabled: !canManageClub || draftName.trimmedOrNil.map { $0 == club.name } ?? true,
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
                            canRemove: canRemoveMember(member, canManage: canManageAdmins),
                            adminToggle: { newValue in
                                toggleAdmin(memberID: member.id, isAdmin: newValue)
                            },
                            onRemove: { memberPendingRemoval = member }
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
                if canManageClub {
                    Button {
                        showingInvite = true
                    } label: {
                        Label("Invite Members", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    PermissionsHelpRow(
                        message: canManageAdmins
                            ? "Toggle admin to grant a member the same management abilities you have. The club creator is always admin and cannot be demoted. Remove a member to drop their books, ratings, and notes from the club and revoke their iCloud access."
                            : "You're an admin: you can rename the club and share the invite link. Only the creator can promote other admins, remove members, or delete the club."
                    )
                } else {
                    PermissionsHelpRow(
                        message: "The creator and other admins manage invitations and admin permissions."
                    )
                }
            } header: {
                SectionTitle(title: "Permissions")
            }
            .bookLoomListRow()

            Section {
                ClubDeleteCard(
                    canDelete: canDelete,
                    clubName: club.name,
                    isDeleting: isDeleting,
                    onTapDelete: { showingDeleteConfirmation = true }
                )
            } header: {
                SectionTitle(title: canDelete ? "Delete Club" : "Leave Club")
            }
            .bookLoomListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Manage Club")
        .bookLoomNavigationBar()
        .sheet(isPresented: $showingInvite) {
            InviteView(club: club)
        }
        .confirmationDialog(
            canDelete ? "Delete \(club.name)?" : "Leave \(club.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(canDelete ? "Delete Club" : "Leave Club", role: .destructive) {
                deleteClub()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if canDelete {
                Text("This removes the club and its proposals, meetings, votes, ratings, and notes from this device, and from anyone you've shared it with.")
            } else {
                Text("This removes the club from this device. The creator's copy is unaffected.")
            }
        }
        .confirmationDialog(
            "Remove member?",
            isPresented: Binding(
                get: { memberPendingRemoval != nil },
                set: { if !$0 { memberPendingRemoval = nil } }
            ),
            presenting: memberPendingRemoval,
            actions: { target in
                Button("Remove \(target.name)", role: .destructive) {
                    removeMember(target)
                }
                Button("Cancel", role: .cancel) {}
            },
            message: { _ in
                Text("Their books, ratings, notes, votes, and RSVPs will be cleared from the club for everyone, and their iCloud sharing access will be revoked.")
            }
        )
        .onAppear {
            draftName = club.name
        }
        .task {
            backfillCreatorIfNeeded()
        }
    }

    private func isCreator(_ member: ClubMemberDigest) -> Bool {
        !club.creatorMemberID.isEmpty && member.id == club.creatorMemberID
    }

    private func canToggleAdmin(for member: ClubMemberDigest, canManage: Bool) -> Bool {
        guard canManage else { return false }
        // Name-keyed digests have no MemberIdentity.memberID, so admin status
        // would never round-trip through CloudKit.
        guard !member.isNameOnly else { return false }
        if member.id == club.creatorMemberID { return false }
        return true
    }

    private func canRemoveMember(_ member: ClubMemberDigest, canManage: Bool) -> Bool {
        guard canManage else { return false }
        guard !member.isNameOnly else { return false }
        if member.id == club.creatorMemberID { return false }
        if member.id == memberIdentity.memberID { return false }
        return true
    }

    private func removeMember(_ member: ClubMemberDigest) {
        let removedID = member.id
        guard !removedID.isEmpty, removedID != club.creatorMemberID else { return }
        club.removeMember(memberID: removedID)
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        } catch {
            assertionFailure("Failed to publish member removal: \(error.localizedDescription)")
        }
        if Features.cloudKitSharing, club.shareIsActive {
            // The refresh waits for the CloudKit deletion so the next merge
            // doesn't re-import the just-removed snapshot.
            Task { @MainActor in
                try? await CloudKitSharingService.shared.removeMemberSnapshot(for: club, memberID: removedID)
                await SharedClubSync.refreshIfNeeded(
                    club,
                    context: context,
                    localMemberID: memberIdentity.memberID,
                    localMemberName: memberIdentity.name
                )
            }
        }
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
        let localID = memberIdentity.memberID
        guard club.isAdmin(memberID: localID),
              let trimmed = draftName.trimmedOrNil,
              trimmed != club.name else { return }
        club.name = trimmed
        club.nameUpdatedAt = .now
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: localID,
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
    let canDelete: Bool
    let clubName: String
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
            return canDelete ? "Deleting…" : "Leaving…"
        }
        return canDelete ? "Delete Club" : "Leave Club"
    }

    private var message: String {
        canDelete
            ? "Permanently removes “\(clubName)” from this device and from anyone you've shared it with. This can't be undone."
            : "Removes “\(clubName)” from this device. The creator's copy and other members' copies are unaffected."
    }
}

private struct ClubMemberRow: View {
    let member: ClubMemberDigest
    let isCreator: Bool
    let isAdmin: Bool
    let canToggleAdmin: Bool
    let canRemove: Bool
    let adminToggle: @MainActor (Bool) -> Void
    let onRemove: @MainActor () -> Void

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

            if canRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "person.fill.xmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .accessibilityLabel("Remove \(member.name)")
            }
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
            HStack(spacing: 8) {
                Text("Admin")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
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
            }
            .accessibilityElement(children: .combine)
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
