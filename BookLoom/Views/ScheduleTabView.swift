import SwiftUI
import SwiftData

/// Top-level Schedule tab. Lists upcoming and past meetings for the active
/// club and lets members schedule the next discussion.
struct ScheduleTabView: View {
    var body: some View {
        ClubScopedScaffold(title: "Schedule") { club in
            ScheduleTabContent(club: club)
        }
    }
}

private struct ScheduleTabContent: View {
    @Environment(\.modelContext) private var context
    @Bindable var club: BookClub
    @Query(sort: \ClubMeeting.scheduledAt) private var meetings: [ClubMeeting]

    @State private var showingScheduleMeeting = false

    var body: some View {
        let upcoming = upcomingMeetings
        let past = pastMeetings
        let currentRead = club.sections.current

        List {
            Section {
                if upcoming.isEmpty && past.isEmpty {
                    InlineEmptyState(
                        systemImage: "calendar",
                        title: "No Meetings Yet",
                        message: currentRead == nil
                            ? "Pick a current book before scheduling the next discussion."
                            : "Schedule the next discussion for the current read."
                    )
                    .bookLoomListRow()
                } else if upcoming.isEmpty {
                    InlineEmptyState(
                        systemImage: "calendar.badge.plus",
                        title: "No Upcoming Meetings",
                        message: currentRead == nil
                            ? "Pick a current book before scheduling the next discussion."
                            : "Schedule the next discussion for the current read."
                    )
                    .bookLoomListRow()
                } else {
                    ForEach(upcoming) { meeting in
                        NavigationLink(value: meeting) {
                            MeetingRow(meeting: meeting)
                        }
                        .bookLoomListRow()
                    }
                }
            } header: {
                if !upcoming.isEmpty {
                    SectionTitle(title: "Upcoming", detail: "\(upcoming.count)")
                }
            }

            if !past.isEmpty {
                Section {
                    ForEach(past) { meeting in
                        NavigationLink(value: meeting) {
                            MeetingRow(meeting: meeting)
                        }
                        .bookLoomListRow()
                    }
                } header: {
                    SectionTitle(title: "Past", detail: "\(past.count)")
                }
            }
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationDestination(for: ClubMeeting.self) { meeting in
            MeetingDetailView(meeting: meeting)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingScheduleMeeting = true
                } label: {
                    Label("Schedule Meeting", systemImage: "calendar.badge.plus")
                }
                .disabled(currentRead == nil)
            }
        }
        .sheet(isPresented: $showingScheduleMeeting) {
            ScheduleMeetingView(club: club, currentSubmission: currentRead)
        }
    }

    private var clubMeetings: [ClubMeeting] {
        meetings.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private var upcomingMeetings: [ClubMeeting] {
        clubMeetings
            .filter { !$0.isCompleted && $0.scheduledAt >= .now }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var pastMeetings: [ClubMeeting] {
        clubMeetings
            .filter { $0.isCompleted || $0.scheduledAt < .now }
            .sorted { ($0.completedAt ?? $0.scheduledAt) > ($1.completedAt ?? $1.scheduledAt) }
    }
}
