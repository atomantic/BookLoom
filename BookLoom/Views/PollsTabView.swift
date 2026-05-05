import SwiftUI
import SwiftData

/// Top-level Polls tab. Lists every selection poll for the active club and
/// lets members start a new ranked vote when at least two proposals exist.
struct PollsTabView: View {
    var body: some View {
        ClubScopedScaffold(title: "Polls") { club in
            PollsTabContent(club: club)
        }
    }
}

private struct PollsTabContent: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity
    @Bindable var club: BookClub
    @Query(sort: \SelectionPoll.createdAt, order: .reverse) private var polls: [SelectionPoll]
    @Query(sort: \BookSubmission.submittedAt) private var submissions: [BookSubmission]

    @State private var showingStartPoll = false

    var body: some View {
        let candidates = clubSubmissions
        let proposed = candidates.filter { $0.status == .proposed }
        let visible = clubPolls
        let openPolls = visible.filter(\.isOpen)
        let closedPolls = visible.filter { !$0.isOpen }

        List {
            Section {
                if visible.isEmpty {
                    InlineEmptyState(
                        systemImage: "list.number",
                        title: "No Polls Yet",
                        message: proposed.count < 2
                            ? "Add at least two proposals before starting a vote."
                            : "Start a ranked vote to pick the next read."
                    )
                    .bookLoomListRow()
                }

                if !openPolls.isEmpty {
                    ForEach(openPolls) { poll in
                        NavigationLink(value: poll) {
                            SelectionPollRow(poll: poll, candidates: candidates)
                        }
                        .bookLoomListRow()
                    }
                }
            } header: {
                if !openPolls.isEmpty {
                    SectionTitle(title: "Open", detail: "\(openPolls.count)")
                }
            }

            if !closedPolls.isEmpty {
                Section {
                    ForEach(closedPolls) { poll in
                        NavigationLink(value: poll) {
                            SelectionPollRow(poll: poll, candidates: candidates)
                        }
                        .bookLoomListRow()
                    }
                } header: {
                    SectionTitle(title: "Closed", detail: "\(closedPolls.count)")
                }
            }
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationDestination(for: SelectionPoll.self) { poll in
            SelectionPollDetailView(poll: poll, candidates: candidates)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingStartPoll = true
                } label: {
                    Label("Start Poll", systemImage: "plus")
                }
                .disabled(proposed.count < 2)
            }
        }
        .sheet(isPresented: $showingStartPoll) {
            StartPollView(club: club, candidates: proposed)
        }
    }

    private var clubSubmissions: [BookSubmission] {
        submissions.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }

    private var clubPolls: [SelectionPoll] {
        polls.filter { $0.bookClub?.persistentModelID == club.persistentModelID }
    }
}
