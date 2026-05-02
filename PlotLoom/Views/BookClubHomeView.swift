import SwiftUI
import SwiftData

struct BookClubHomeView: View {
    @Environment(\.modelContext) private var context
    @Bindable var club: BookClub

    @State private var showingInvite: Bool = false
    @State private var showingPickConfirmation: Bool = false

    var body: some View {
        List {
            Section("Currently Reading") {
                if let current = currentSubmission {
                    NavigationLink(value: current) {
                        SubmissionRow(submission: current)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Mark Complete") {
                            current.status = .completed
                            current.completedAt = .now
                        }
                        .tint(.green)
                    }
                } else {
                    Text("No book chosen yet. Add proposals below, then tap Pick Random.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Proposed") {
                if proposedSubmissions.isEmpty {
                    Text("No proposals yet. Add a book to start.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(proposedSubmissions) { sub in
                        NavigationLink(value: sub) {
                            SubmissionRow(submission: sub)
                        }
                    }
                    .onDelete { offsets in
                        delete(proposedSubmissions, at: offsets)
                    }
                }
            }

            if !completedSubmissions.isEmpty {
                Section("Read") {
                    ForEach(completedSubmissions) { sub in
                        NavigationLink(value: sub) {
                            SubmissionRow(submission: sub)
                        }
                    }
                    .onDelete { offsets in
                        delete(completedSubmissions, at: offsets)
                    }
                }
            }
        }
        .navigationTitle(club.name)
        .navigationDestination(for: BookSubmission.self) { sub in
            SubmissionDetailView(submission: sub)
        }
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
                    showingPickConfirmation = true
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
        .confirmationDialog(
            "Pick the next book?",
            isPresented: $showingPickConfirmation,
            titleVisibility: .visible
        ) {
            Button("Pick Random Book") {
                pickRandomNext()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if currentSubmission != nil {
                Text("This will mark the current book as completed and pick a random proposal as the next read.")
            } else {
                Text("This will pick a random proposal as the current read.")
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

    private func delete(_ items: [BookSubmission], at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
    }
}

private struct SubmissionRow: View {
    @Bindable var submission: BookSubmission

    var body: some View {
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
