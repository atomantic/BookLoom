import SwiftData
import SwiftUI

struct SelectionPollRow: View {
    @Bindable var poll: SelectionPoll
    let candidates: [BookSubmission]

    var body: some View {
        let tally = SelectionPollScorer.tally(votes: poll.votes ?? [], candidateIDs: poll.candidateIDs)
        let leader = tally.leader.flatMap { result in
            candidates.first { $0.selectionID == result.id }
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(poll.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BookLoomStyle.ink)
                    Text("\((poll.votes ?? []).count) ballots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TintedCapsuleLabel(
                    text: poll.status.displayName,
                    tint: poll.isOpen ? BookLoomStyle.sage : BookLoomStyle.indigo,
                    horizontalPadding: 7,
                    verticalPadding: 3
                )
            }

            if let leader {
                Label(tally.hasTie ? "Tie includes \(leader.displayTitle)" : "Leader: \(leader.displayTitle)", systemImage: tally.hasTie ? "equal.circle.fill" : "chart.bar.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("No votes yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .bookLoomCard(padding: 10)
    }
}

struct StartPollView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var club: BookClub
    let candidates: [BookSubmission]

    @State private var title: String = "Next Book Vote"
    @State private var hideVoterNames: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Poll") {
                    TextField("Title", text: $title)
                    Toggle("Hide voter names", isOn: $hideVoterNames)
                }

                Section("Candidates") {
                    ForEach(candidates) { candidate in
                        Label(candidate.displayTitle, systemImage: "book.closed")
                    }
                }
            }
            .navigationTitle("Start Poll")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: save)
                        .disabled(candidates.count < 2)
                }
            }
        }
    }

    private func save() {
        let poll = SelectionPoll(
            title: title.trimmedOrNil ?? "Next Book Vote",
            candidates: candidates,
            isAnonymousResults: hideVoterNames
        )
        poll.createdByMemberID = memberIdentity.memberID
        context.insert(poll)
        club.addSelectionPoll(poll)
        do {
            try SharedClubSync.saveAndPublish(
                context: context,
                club: club,
                localMemberID: memberIdentity.memberID,
                localMemberName: memberIdentity.name
            )
        } catch {
            assertionFailure("Failed to save poll: \(error.localizedDescription)")
        }
        dismiss()
    }
}

struct SelectionPollDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(MemberIdentity.self) private var memberIdentity

    @Bindable var poll: SelectionPoll
    let candidates: [BookSubmission]

    @State private var firstPickID: String = ""
    @State private var secondPickID: String = ""
    @State private var thirdPickID: String = ""

    var body: some View {
        let candidateIDs = poll.candidateIDs
        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.selectionID, $0) })
        let orderedCandidates = candidateIDs.compactMap { candidatesByID[$0] }
        let tally = SelectionPollScorer.tally(votes: poll.votes ?? [], candidateIDs: candidateIDs)

        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(poll.displayTitle)
                        .font(.headline.bold())
                        .foregroundStyle(BookLoomStyle.ink)
                    Text(poll.isAnonymousResults ? "Rank up to three books. Results hide voter names." : "Rank up to three books. Member ballots are visible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .bookLoomCard(padding: 12)
            }
            .bookLoomListRow(top: 6, bottom: 8)

            if poll.isOpen {
                Section {
                    VStack(spacing: 10) {
                        rankPicker("First choice", selection: $firstPickID, candidates: orderedCandidates, allowEmpty: false)
                        rankPicker("Second choice", selection: $secondPickID, candidates: orderedCandidates, allowEmpty: true)
                        rankPicker("Third choice", selection: $thirdPickID, candidates: orderedCandidates, allowEmpty: true)

                        Button {
                            saveVote()
                        } label: {
                            Label("Save Ballot", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(firstPickID.isEmpty)
                    }
                    .bookLoomCard(padding: 12)
                } header: {
                    SectionTitle(title: "Your Ranking")
                }
                .bookLoomListRow()
            }

            Section {
                ForEach(tally.results) { result in
                    let candidate = candidatesByID[result.id]
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate?.displayTitle ?? "Unknown book")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(BookLoomStyle.ink)
                            Text("\(result.firstPlaceVotes) first-place votes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(result.score)")
                            .font(.headline.bold())
                            .foregroundStyle(BookLoomStyle.plum)
                    }
                    .bookLoomCard(padding: 10)
                }

                if tally.hasTie {
                    Label("Tie at the top. Keep voting or use the random picker as a tiebreaker.", systemImage: "equal.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .bookLoomCard(padding: 10)
                }
            } header: {
                SectionTitle(title: "Results", detail: "\((poll.votes ?? []).count)")
            }
            .bookLoomListRow()

            if !poll.isAnonymousResults {
                Section {
                    ForEach((poll.votes ?? []).sorted { $0.updatedAt > $1.updatedAt }) { vote in
                        Text(vote.memberName.trimmedOrNil ?? "Unknown member")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BookLoomStyle.ink)
                            .bookLoomCard(padding: 10)
                    }
                } header: {
                    SectionTitle(title: "Voters")
                }
                .bookLoomListRow()
            }
        }
        .bookLoomListStyle()
        .scrollContentBackground(.hidden)
        .bookLoomScreenBackground()
        .navigationTitle("Poll")
        .bookLoomNavigationBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    promoteWinner(tally)
                } label: {
                    Label("Promote Winner", systemImage: "checkmark.seal")
                }
                .disabled(!canPromote(tally))
            }
        }
        .onAppear(perform: loadOwnVote)
    }

    @ViewBuilder
    private func rankPicker(_ title: String, selection: Binding<String>, candidates: [BookSubmission], allowEmpty: Bool) -> some View {
        Picker(title, selection: selection) {
            if allowEmpty {
                Text("None").tag("")
            }
            ForEach(candidates) { candidate in
                Text(candidate.displayTitle).tag(candidate.selectionID)
            }
        }
    }

    private func loadOwnVote() {
        guard let vote = poll.vote(for: memberIdentity.memberID, memberName: memberIdentity.name) else { return }
        let ranks = vote.rankedSubmissionIDs
        firstPickID = ranks[safe: 0] ?? ""
        secondPickID = ranks[safe: 1] ?? ""
        thirdPickID = ranks[safe: 2] ?? ""
    }

    private func saveVote() {
        poll.replaceVote(
            memberID: memberIdentity.memberID,
            memberName: memberIdentity.name,
            rankedSubmissionIDs: [firstPickID, secondPickID, thirdPickID]
        )
        savePollChanges()
    }

    private func canPromote(_ tally: SelectionPollTally) -> Bool {
        poll.isOpen && !tally.hasTie && (tally.leader?.score ?? 0) > 0
    }

    private func promoteWinner(_ tally: SelectionPollTally) {
        guard let winnerID = tally.leader?.id,
              let winner = candidates.first(where: { $0.selectionID == winnerID }),
              let club = poll.bookClub else {
            return
        }
        SelectionPollCoordinator.promoteWinner(winner, in: club, actorMemberID: memberIdentity.memberID)
        DiscussionPromptLibrary.ensureStarterPrompts(for: winner, context: context)
        poll.status = .closed
        poll.winnerSubmissionID = winner.selectionID
        savePollChanges()
    }

    private func savePollChanges() {
        do {
            try context.save()
            if let club = poll.bookClub {
                SharedClubSync.publishIfNeeded(
                    club,
                    context: context,
                    localMemberID: memberIdentity.memberID,
                    localMemberName: memberIdentity.name
                )
            }
        } catch {
            assertionFailure("Failed to save poll changes: \(error.localizedDescription)")
        }
    }
}
