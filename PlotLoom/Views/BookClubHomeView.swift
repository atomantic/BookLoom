import SwiftUI
import SwiftData

struct BookClubHomeView: View {
    @Bindable var club: BookClub

    @State private var showingInvite: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section("Currently Reading") {
                    if let current = currentSubmission {
                        SubmissionRow(submission: current)
                    } else {
                        Text("No book chosen yet. Add submissions, then pick one.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Proposed") {
                    if proposedSubmissions.isEmpty {
                        Text("No proposals yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(proposedSubmissions) { sub in
                            SubmissionRow(submission: sub)
                        }
                    }
                }

                Section("Read") {
                    if completedSubmissions.isEmpty {
                        Text("Nothing finished yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(completedSubmissions) { sub in
                            SubmissionRow(submission: sub)
                        }
                    }
                }
            }
            .navigationTitle(club.name)
            .toolbar {
                ToolbarItem {
                    NavigationLink {
                        AddSubmissionView(club: club)
                    } label: {
                        Label("Add Book", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        pickRandomNext()
                    } label: {
                        Label("Pick Random", systemImage: "shuffle")
                    }
                    .disabled(proposedSubmissions.isEmpty)
                }
                if club.isOwner {
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            showingInvite = true
                        } label: {
                            Label("Invite Members", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingInvite) {
                InviteView(club: club)
            }
        }
    }

    private var allSubmissions: [BookSubmission] {
        club.submissions ?? []
    }

    private var currentSubmission: BookSubmission? {
        allSubmissions.first { $0.status == .current }
    }

    private var proposedSubmissions: [BookSubmission] {
        allSubmissions
            .filter { $0.status == .proposed }
            .sorted { $0.submittedAt < $1.submittedAt }
    }

    private var completedSubmissions: [BookSubmission] {
        allSubmissions
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private func pickRandomNext() {
        if let current = currentSubmission {
            current.status = .completed
            current.completedAt = .now
        }
        guard let pick = BookPicker.pickNext(from: proposedSubmissions) else { return }
        pick.status = .current
        pick.pickedAt = .now
    }
}

private struct SubmissionRow: View {
    @Bindable var submission: BookSubmission

    var body: some View {
        NavigationLink {
            SubmissionDetailView(submission: submission)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(submission.title.isEmpty ? "Untitled" : submission.title)
                    .font(.headline)
                if !submission.author.isEmpty {
                    Text(submission.author).foregroundStyle(.secondary)
                }
                if !submission.submittedBy.isEmpty {
                    Text("Submitted by \(submission.submittedBy)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
