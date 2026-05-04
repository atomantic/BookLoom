import SwiftData
import SwiftUI

struct MeetingRow: View {
    @Bindable var meeting: ClubMeeting

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: meeting.isCompleted ? "calendar.badge.checkmark" : "calendar")
                .font(.title3.weight(.semibold))
                .foregroundStyle(meeting.isCompleted ? BookLoomStyle.sage : BookLoomStyle.indigo)
                .frame(minWidth: 28, minHeight: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                    .lineLimit(2)
                Text(meeting.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !meeting.location.trimmed.isEmpty {
                    Label(meeting.location.trimmed, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            let acceptedCount = (meeting.rsvps ?? []).filter { $0.status == .attending }.count
            TintedCapsuleLabel(text: "\(acceptedCount) going", tint: BookLoomStyle.sage, horizontalPadding: 7, verticalPadding: 3)
        }
        .bookLoomCard(padding: 10)
    }
}

struct ScheduleMeetingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var club: BookClub
    let currentSubmission: BookSubmission?

    @State private var title: String = ""
    @State private var scheduledAt: Date = Date.now.addingTimeInterval(7 * 24 * 60 * 60)
    @State private var hostName: String = ""
    @State private var location: String = ""
    @State private var meetingURL: String = ""
    @State private var agenda: String = ""
    @State private var selectedReminderOffsets: Set<Int> = [
        MeetingReminderOffset.oneDay.rawValue,
        MeetingReminderOffset.oneHour.rawValue
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Meeting") {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $scheduledAt)
                    TextField("Host", text: $hostName)
                    TextField("Location", text: $location)
                    TextField("Video link", text: $meetingURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                }

                Section("Reminders") {
                    ForEach(MeetingReminderOffset.allCases) { offset in
                        Toggle(offset.displayName, isOn: reminderBinding(for: offset.rawValue))
                    }
                }

                Section("Agenda") {
                    TextField("Topics, format, or host notes", text: $agenda, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let currentSubmission {
                    Section("Book") {
                        LabeledContent("Current read", value: currentSubmission.displayTitle)
                        Text("Starter discussion prompts will be added to this book if it does not have any yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Schedule Meeting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(scheduledAt <= .now)
                }
            }
            .onAppear {
                if hostName.isEmpty {
                    hostName = memberIdentity.name
                }
                if title.isEmpty, let currentSubmission {
                    title = "\(currentSubmission.displayTitle) Discussion"
                }
            }
        }
    }

    private func reminderBinding(for offset: Int) -> Binding<Bool> {
        Binding(
            get: { selectedReminderOffsets.contains(offset) },
            set: { isSelected in
                if isSelected {
                    selectedReminderOffsets.insert(offset)
                } else {
                    selectedReminderOffsets.remove(offset)
                }
            }
        )
    }

    private func save() {
        let meeting = ClubMeeting(
            title: title.trimmed,
            scheduledAt: scheduledAt,
            hostName: hostName.trimmedOrNil ?? memberIdentity.name,
            hostMemberID: memberIdentity.memberID,
            location: location.trimmed,
            meetingURL: meetingURL.trimmed,
            reminderOffsets: Array(selectedReminderOffsets),
            agenda: agenda.trimmed
        )
        context.insert(meeting)
        club.addMeeting(meeting)
        meeting.bookSubmission = currentSubmission
        meeting.upsertRSVP(
            memberID: memberIdentity.memberID,
            memberName: memberIdentity.name,
            status: .attending
        )
        if let currentSubmission {
            DiscussionPromptLibrary.ensureStarterPrompts(for: currentSubmission, context: context)
        }
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        } catch {
            assertionFailure("Failed to save meeting: \(error.localizedDescription)")
        }
        Task { await MeetingReminderScheduler.scheduleReminders(for: meeting) }
        dismiss()
    }
}

struct MeetingDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Bindable var meeting: ClubMeeting

    @State private var selectedStatus: MeetingRSVPStatus = .attending
    @State private var bringingNote: String = ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(meeting.displayTitle)
                        .font(.headline.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                    Label(meeting.scheduledAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    if !meeting.location.trimmed.isEmpty {
                        Label(meeting.location.trimmed, systemImage: "mappin.and.ellipse")
                    }
                    if let url = meeting.meetingURL.trimmedOrNil.flatMap(URL.init(string:)) {
                        Link(destination: url) {
                            Label("Open meeting link", systemImage: "video.fill")
                        }
                    }
                    if let book = meeting.bookSubmission {
                        Label(book.displayTitle, systemImage: "book.closed.fill")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .bookLoomCard(padding: 12)
            }
            .bookLoomListRow(top: 6, bottom: 8)

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("RSVP", selection: $selectedStatus) {
                        ForEach(MeetingRSVPStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Bringing, hosting note, or dietary note", text: $bringingNote, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        saveRSVP()
                    } label: {
                        Label("Save RSVP", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .bookLoomCard(padding: 12)
            } header: {
                SectionTitle(title: "Your RSVP")
            }
            .bookLoomListRow()

            if !meeting.agenda.trimmed.isEmpty {
                Section {
                    Text(meeting.agenda.trimmed)
                        .font(.callout)
                        .foregroundStyle(BookLoomStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .bookLoomCard(padding: 12)
                } header: {
                    SectionTitle(title: "Agenda")
                }
                .bookLoomListRow()
            }

            Section {
                let sortedRSVPs = (meeting.rsvps ?? []).sorted { $0.updatedAt > $1.updatedAt }
                if sortedRSVPs.isEmpty {
                    InlineEmptyState(systemImage: "person.2", title: "No RSVPs", message: "Responses appear here as members weigh in.")
                } else {
                    ForEach(sortedRSVPs) { rsvp in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rsvp.memberName.trimmedOrNil ?? "Unknown member")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(BookLoomStyle.ink)
                                if !rsvp.bringingNote.trimmed.isEmpty {
                                    Text(rsvp.bringingNote.trimmed)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(rsvp.status.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .bookLoomCard(padding: 10)
                    }
                }
            } header: {
                SectionTitle(title: "Responses", detail: "\((meeting.rsvps ?? []).count)")
            }
            .bookLoomListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Meeting")
        .bookLoomNavigationBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    meeting.completedAt = meeting.isCompleted ? nil : .now
                    saveMeetingChanges()
                } label: {
                    Label(meeting.isCompleted ? "Reopen" : "Mark Complete", systemImage: meeting.isCompleted ? "arrow.uturn.backward" : "checkmark.seal")
                }
            }
        }
        .onAppear {
            let ownRSVP = meeting.rsvp(for: memberIdentity.memberID, memberName: memberIdentity.name)
            selectedStatus = ownRSVP?.status ?? .attending
            bringingNote = ownRSVP?.bringingNote ?? ""
        }
    }

    private func saveRSVP() {
        meeting.upsertRSVP(
            memberID: memberIdentity.memberID,
            memberName: memberIdentity.name,
            status: selectedStatus,
            bringingNote: bringingNote
        )
        saveMeetingChanges()
    }

    private func saveMeetingChanges() {
        do {
            try context.save()
            if let club = meeting.bookClub {
                SharedClubSync.publishIfNeeded(
                    club,
                    context: context,
                    localMemberID: memberIdentity.memberID,
                    localMemberName: memberIdentity.name
                )
            }
        } catch {
            assertionFailure("Failed to save meeting changes: \(error.localizedDescription)")
        }
    }
}
