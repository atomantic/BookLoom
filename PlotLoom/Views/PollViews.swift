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
                        .foregroundStyle(PlotLoomStyle.ink)
                    Text("\((poll.votes ?? []).count) ballots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TintedCapsuleLabel(
                    text: poll.status.displayName,
                    tint: poll.isOpen ? PlotLoomStyle.sage : PlotLoomStyle.indigo,
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
        .plotLoomCard(padding: 10)
    }
}

struct StartPollView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

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
        context.insert(poll)
        club.addSelectionPoll(poll)
        try? context.save()
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
                        .foregroundStyle(PlotLoomStyle.ink)
                    Text(poll.isAnonymousResults ? "Rank up to three books. Results hide voter names." : "Rank up to three books. Member ballots are visible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .plotLoomCard(padding: 12)
            }
            .plotLoomListRow(top: 6, bottom: 8)

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
                    .plotLoomCard(padding: 12)
                } header: {
                    SectionTitle(title: "Your Ranking")
                }
                .plotLoomListRow()
            }

            Section {
                ForEach(tally.results) { result in
                    let candidate = candidatesByID[result.id]
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate?.displayTitle ?? "Unknown book")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(PlotLoomStyle.ink)
                            Text("\(result.firstPlaceVotes) first-place votes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(result.score)")
                            .font(.headline.bold())
                            .foregroundStyle(PlotLoomStyle.plum)
                    }
                    .plotLoomCard(padding: 10)
                }

                if tally.hasTie {
                    Label("Tie at the top. Keep voting or use the random picker as a tiebreaker.", systemImage: "equal.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .plotLoomCard(padding: 10)
                }
            } header: {
                SectionTitle(title: "Results", detail: "\((poll.votes ?? []).count)")
            }
            .plotLoomListRow()

            if !poll.isAnonymousResults {
                Section {
                    ForEach((poll.votes ?? []).sorted { $0.updatedAt > $1.updatedAt }) { vote in
                        Text(vote.memberName.trimmedOrNil ?? "Unknown member")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PlotLoomStyle.ink)
                            .plotLoomCard(padding: 10)
                    }
                } header: {
                    SectionTitle(title: "Voters")
                }
                .plotLoomListRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .plotLoomScreenBackground()
        .navigationTitle("Poll")
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
        try? context.save()
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
        SelectionPollCoordinator.promoteWinner(winner, in: club)
        DiscussionPromptLibrary.ensureStarterPrompts(for: winner, context: context)
        poll.status = .closed
        poll.winnerSubmissionID = winner.selectionID
        try? context.save()
    }
}

