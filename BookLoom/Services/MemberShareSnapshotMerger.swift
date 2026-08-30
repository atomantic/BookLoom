import Foundation
import SwiftData

extension MemberShareSnapshotStore {
    /// Additive merge. Reconciles SwiftData rows with the union of all member
    /// snapshots. Local items authored by `localMemberID` are preserved as-is
    /// — they may carry unpublished updates that haven't reached CloudKit yet.
    static func merge(
        snapshots: [MemberShareSnapshot],
        into club: BookClub,
        context: ModelContext,
        localMemberID: String,
        reactivatedMemberIDs: Set<String> = []
    ) throws {
        // 1. Apply club meta from the snapshot that carries it (the owner's).
        if let metaSnapshot = snapshots
            .filter({ $0.clubMeta != nil })
            .max(by: { clubMetaVersion($0) < clubMetaVersion($1) }),
           let meta = metaSnapshot.clubMeta {
            if club.name != meta.name { club.name = meta.name }
            let nextNameUpdatedAt = meta.nameUpdatedAt ?? club.nameUpdatedAt
            if club.nameUpdatedAt != nextNameUpdatedAt { club.nameUpdatedAt = nextNameUpdatedAt }
            if club.createdAt != meta.createdAt { club.createdAt = meta.createdAt }
            if club.cloudZoneName.isEmpty {
                club.cloudZoneName = meta.cloudZoneName
            }
            let participants = max(1, meta.shareParticipantCount)
            if club.shareParticipantCount != participants { club.shareParticipantCount = participants }
            if let creator = meta.creatorMemberID?.trimmedOrNil, club.creatorMemberID != creator {
                club.creatorMemberID = creator
            }
            if let admins = meta.adminMemberIDs {
                let nextAdmins = Set(admins.filter { !$0.isEmpty })
                if club.adminMemberIDs != nextAdmins { club.adminMemberIDs = nextAdmins }
            }
            if let removed = meta.removedMemberIDs {
                let nextRemoved = Set(removed.filter { !$0.isEmpty })
                if club.removedMemberIDs != nextRemoved { club.removedMemberIDs = nextRemoved }
            }
            let nextMetaUpdatedAt = meta.metadataUpdatedAt ?? metaSnapshot.capturedAt
            if club.clubMetaUpdatedAt != nextMetaUpdatedAt { club.clubMetaUpdatedAt = nextMetaUpdatedAt }
            // Identity bindings are applied only by
            // `MemberSnapshotAuthorization`, after CloudKit provenance has
            // authenticated this metadata. Applying decoded values here would
            // also overwrite bindings the owner just enrolled during legacy
            // migration before they can be republished.
        }

        // Only owner-side authorization can supply these IDs, after proving
        // that an accepted CloudKit participant matches the removed identity.
        // Apply this after remote ClubMeta so a stale owner snapshot carrying
        // the old tombstones cannot immediately overwrite the reactivation.
        if club.isShareOwner, !reactivatedMemberIDs.isEmpty {
            var nextRemoved = club.removedMemberIDs
            nextRemoved.subtract(reactivatedMemberIDs)
            club.removedMemberIDs = nextRemoved
        }

        let validProposers = club.adminMemberIDs.union(
            club.creatorMemberID.isEmpty ? [] : [club.creatorMemberID]
        )
        let latestProposal = snapshots.lazy
            .compactMap(\.nameProposal)
            .filter { validProposers.contains($0.proposerMemberID) && !$0.name.isEmpty }
            .max(by: { $0.updatedAt < $1.updatedAt })
        if let latestProposal, latestProposal.updatedAt > club.nameUpdatedAt {
            club.name = latestProposal.name
            club.nameUpdatedAt = latestProposal.updatedAt
            if club.isOwner, club.clubMetaUpdatedAt < latestProposal.updatedAt {
                club.clubMetaUpdatedAt = latestProposal.updatedAt
            }
        }
        club.shareIsActive = true

        // Removed members' snapshots must be filtered before building canonical
        // sets — otherwise step 5's "delete non-canonical, non-local" pass
        // would re-import their rows on every merge.
        let memberKey: (String) -> String = { club.canonicalMemberKey(for: $0) }
        let removedAuthors = club.removedMemberIDs
        let removedPersonKeys = Set(removedAuthors.map(memberKey))
        let activeSnapshots = removedPersonKeys.isEmpty
            ? snapshots
            : snapshots.filter { !removedPersonKeys.contains(memberKey($0.authorMemberID)) }

        // 2. Index existing local rows by stable ID for upsert.
        //
        // Predicate-scope each fetch to this club so SQLite filters server-side
        // instead of loading every row and filtering in memory (these run on
        // every CloudKit sync tick). The fetches use `try` rather than `try?`:
        // a failing/migrating store must propagate out of the throwing `merge()`
        // — swallowing it would hand the delete passes below (steps 5/6/7/8) an
        // empty "existing" index against a full canonical set, mass-deleting
        // remote-authored rows on a transient read failure.
        let clubID = club.persistentModelID
        let submissionPredicate = #Predicate<BookSubmission> { $0.bookClub?.persistentModelID == clubID }
        let localSubmissions = try context.fetch(FetchDescriptor<BookSubmission>(predicate: submissionPredicate))
        var submissionsByID: [String: BookSubmission] = [:]
        for sub in localSubmissions where !sub.selectionID.isEmpty {
            submissionsByID[sub.selectionID] = sub
        }
        let preMergeSubmissions = Array(submissionsByID.values)
        let promptPredicate = #Predicate<DiscussionPrompt> { $0.submission?.bookClub?.persistentModelID == clubID }
        let localPrompts = try context.fetch(FetchDescriptor<DiscussionPrompt>(predicate: promptPredicate))
        var promptsByID: [String: DiscussionPrompt] = [:]
        for prompt in localPrompts where !prompt.promptID.isEmpty {
            promptsByID[prompt.promptID] = prompt
        }
        let preMergePromptIDs = Set(promptsByID.keys)
        let pollPredicate = #Predicate<SelectionPoll> { $0.bookClub?.persistentModelID == clubID }
        let localPolls = try context.fetch(FetchDescriptor<SelectionPoll>(predicate: pollPredicate))
        var pollsByID: [String: SelectionPoll] = [:]
        for poll in localPolls where !poll.pollID.isEmpty {
            pollsByID[poll.pollID] = poll
        }
        let preMergePollIDs = Set(pollsByID.keys)
        let meetingPredicate = #Predicate<ClubMeeting> { $0.bookClub?.persistentModelID == clubID }
        let localMeetings = try context.fetch(FetchDescriptor<ClubMeeting>(predicate: meetingPredicate))
        var meetingsByID: [String: ClubMeeting] = [:]
        for meeting in localMeetings where !meeting.meetingID.isEmpty {
            meetingsByID[meeting.meetingID] = meeting
        }
        let preMergeMeetingIDs = Set(meetingsByID.keys)

        // 3. Compute canonical sets from snapshots.
        var canonicalSubmissions: [String: MemberShareSnapshot.SubmissionPayload] = [:]
        var statusOverridesByID: [String: [MemberShareSnapshot.StatusOverride]] = [:]
        var detailsOverridesByID: [String: [MemberShareSnapshot.SubmissionDetailsOverride]] = [:]
        var deletionsByID: [String: [MemberShareSnapshot.SubmissionDeletion]] = [:]
        var canonicalPrompts: [String: MemberShareSnapshot.PromptPayload] = [:]
        var canonicalPolls: [String: MemberShareSnapshot.PollPayload] = [:]
        var canonicalMeetings: [String: MemberShareSnapshot.MeetingPayload] = [:]
        var meetingsBySubmissionID: [String: String] = [:]
        var ratingsByKey: [String: MemberShareSnapshot.RatingPayload] = [:] // "<submissionID>|<person>"
        var notesByKey: [String: MemberShareSnapshot.NotePayload] = [:] // "<submissionID>|<memberID>|<createdAt>"
        var votesByKey: [String: MemberShareSnapshot.VotePayload] = [:] // "<pollID>|<person>"
        var rsvpsByKey: [String: MemberShareSnapshot.RSVPPayload] = [:] // "<meetingID>|<person>"

        for snap in activeSnapshots {
            for sub in snap.submissions {
                canonicalSubmissions[sub.selectionID] = sub
            }
            for ov in snap.statusOverrides {
                statusOverridesByID[ov.submissionSelectionID, default: []].append(ov)
            }
            for override in snap.detailsOverrides ?? [] {
                detailsOverridesByID[override.submissionSelectionID, default: []].append(override)
            }
            for deletion in snap.deletedSubmissions ?? [] {
                deletionsByID[deletion.submissionSelectionID, default: []].append(deletion)
            }
            for prompt in snap.prompts {
                canonicalPrompts[prompt.promptID] = prompt
            }
            for poll in snap.polls {
                canonicalPolls[poll.pollID] = poll
            }
            for meeting in snap.meetings {
                canonicalMeetings[meeting.meetingID] = meeting
                if let submissionID = meeting.submissionSelectionID {
                    meetingsBySubmissionID[meeting.meetingID] = submissionID
                }
            }
            for rating in snap.ratings {
                let key = "\(rating.submissionSelectionID)|\(memberKey(rating.memberID))"
                if let existing = ratingsByKey[key], existing.createdAt >= rating.createdAt { continue }
                ratingsByKey[key] = rating
            }
            for note in snap.notes {
                let key = "\(note.submissionSelectionID)|\(memberKey(note.memberID))|\(note.createdAt.timeIntervalSince1970)"
                notesByKey[key] = note
            }
            for vote in snap.votes {
                let key = "\(vote.pollID)|\(memberKey(vote.memberID))"
                if let existing = votesByKey[key], existing.updatedAt >= vote.updatedAt { continue }
                votesByKey[key] = vote
            }
            for rsvp in snap.rsvps {
                let key = "\(rsvp.meetingID)|\(memberKey(rsvp.memberID))"
                if let existing = rsvpsByKey[key], existing.updatedAt >= rsvp.updatedAt { continue }
                rsvpsByKey[key] = rsvp
            }
        }

        let deletedSubmissionIDs = Set(deletionsByID.keys)
        for selectionID in deletedSubmissionIDs {
            if let sub = submissionsByID.removeValue(forKey: selectionID) {
                context.delete(sub)
            }
        }

        // 4. Upsert submissions.
        for (selectionID, payload) in canonicalSubmissions {
            if deletedSubmissionIDs.contains(selectionID) { continue }
            let submission: BookSubmission
            if let existing = submissionsByID[selectionID] {
                submission = existing
            } else {
                submission = BookSubmission()
                context.insert(submission)
                club.addSubmission(submission)
                submissionsByID[selectionID] = submission
            }
            submission.selectionID = payload.selectionID
            submission.title = payload.title
            submission.author = payload.author
            submission.isbn = payload.isbn
            submission.submittedBy = payload.submittedBy
            submission.submittedByMemberID = payload.submittedByMemberID
            submission.submittedAt = payload.submittedAt
            submission.bookDescription = payload.bookDescription
            submission.publishedYear = payload.publishedYear
            submission.coverURL = payload.coverURL
            submission.externalProvider = payload.externalProvider
            submission.externalID = payload.externalID
            submission.coverData = nil

            if let latestDetails = detailsOverridesByID[selectionID]?.max(by: { $0.updatedAt < $1.updatedAt }) {
                submission.title = latestDetails.title
                submission.author = latestDetails.author
                submission.isbn = latestDetails.isbn
                submission.bookDescription = latestDetails.bookDescription
                submission.publishedYear = latestDetails.publishedYear
                submission.coverURL = latestDetails.coverURL
                submission.externalProvider = latestDetails.externalProvider
                submission.externalID = latestDetails.externalID
                submission.coverData = nil
            }

            let overrides = statusOverridesByID[selectionID] ?? []
            if let latest = overrides.max(by: { $0.occurredAt < $1.occurredAt }) {
                submission.statusRaw = latest.statusRaw
                submission.pickedAt = latest.pickedAt
                submission.completedAt = latest.completedAt
            } else {
                submission.statusRaw = payload.initialStatusRaw
                submission.pickedAt = payload.initialPickedAt
                submission.completedAt = payload.initialCompletedAt
            }
            if submission.bookClub?.persistentModelID != clubID {
                club.addSubmission(submission)
            }
        }

        // 5. Delete local submissions not in canonical, except those authored
        //    locally (might be unpublished new additions).
        for (selectionID, sub) in submissionsByID where canonicalSubmissions[selectionID] == nil {
            if isAuthor(localMemberID, of: sub.submittedByMemberID) { continue }
            context.delete(sub)
        }

        // 6. Upsert prompts.
        for (promptID, payload) in canonicalPrompts {
            guard let parent = submissionsByID[payload.submissionSelectionID] else { continue }
            let prompt: DiscussionPrompt
            if let existing = promptsByID[promptID] {
                prompt = existing
            } else {
                prompt = DiscussionPrompt()
                context.insert(prompt)
                promptsByID[promptID] = prompt
            }
            prompt.promptID = payload.promptID
            prompt.question = payload.question
            prompt.orderIndex = payload.orderIndex
            prompt.sourceRaw = payload.sourceRaw
            prompt.createdAt = payload.createdAt
            prompt.isArchived = payload.isArchived
            prompt.createdByMemberID = payload.createdByMemberID
            prompt.submission = parent
        }
        for (promptID, prompt) in promptsByID where canonicalPrompts[promptID] == nil {
            if isAuthor(localMemberID, of: prompt.createdByMemberID) { continue }
            // Starter prompts (empty createdByMemberID) are auto-generated locally
            // and not synced — leave them in place.
            if prompt.createdByMemberID.isEmpty { continue }
            context.delete(prompt)
        }

        // 7. Upsert polls.
        for (pollID, payload) in canonicalPolls {
            let poll: SelectionPoll
            if let existing = pollsByID[pollID] {
                poll = existing
            } else {
                poll = SelectionPoll()
                context.insert(poll)
                club.addSelectionPoll(poll)
                pollsByID[pollID] = poll
            }
            poll.pollID = payload.pollID
            poll.createdByMemberID = payload.createdByMemberID
            poll.title = payload.title
            poll.createdAt = payload.createdAt
            poll.closesAt = payload.closesAt
            poll.statusRaw = payload.statusRaw
            poll.isAnonymousResults = payload.isAnonymousResults
            poll.candidateIDsRaw = payload.candidateIDsRaw
            poll.winnerSubmissionID = payload.winnerSubmissionID
            if poll.bookClub?.persistentModelID != clubID {
                club.addSelectionPoll(poll)
            }
        }
        for (pollID, poll) in pollsByID where canonicalPolls[pollID] == nil {
            if isAuthor(localMemberID, of: poll.createdByMemberID) { continue }
            context.delete(poll)
        }

        // 8. Upsert meetings.
        for (meetingID, payload) in canonicalMeetings {
            let meeting: ClubMeeting
            if let existing = meetingsByID[meetingID] {
                meeting = existing
            } else {
                meeting = ClubMeeting()
                context.insert(meeting)
                club.addMeeting(meeting)
                meetingsByID[meetingID] = meeting
            }
            meeting.meetingID = payload.meetingID
            meeting.title = payload.title
            meeting.scheduledAt = payload.scheduledAt
            meeting.hostName = payload.hostName
            meeting.hostMemberID = payload.hostMemberID
            meeting.location = payload.location
            meeting.meetingURL = payload.meetingURL
            meeting.reminderOffsetsRaw = payload.reminderOffsetsRaw
            meeting.agenda = payload.agenda
            meeting.createdAt = payload.createdAt
            meeting.completedAt = payload.completedAt
            meeting.bookSubmission = payload.submissionSelectionID.flatMap { submissionsByID[$0] }
            if meeting.bookClub?.persistentModelID != clubID {
                club.addMeeting(meeting)
            }
        }
        for (meetingID, meeting) in meetingsByID where canonicalMeetings[meetingID] == nil {
            if isAuthor(localMemberID, of: meeting.hostMemberID) { continue }
            context.delete(meeting)
        }

        // 9. Reconcile per-submission ratings/notes (own ratings/notes are
        //    preserved verbatim; remote authors' are upserted/pruned to match
        //    canonical).
        applyRatings(canonical: ratingsByKey, submissionsByID: submissionsByID, localMemberID: localMemberID, memberKey: memberKey, context: context)
        applyNotes(canonical: notesByKey, submissionsByID: submissionsByID, localMemberID: localMemberID, memberKey: memberKey, context: context)

        // 10. Reconcile votes per poll (one canonical vote per (poll, member)).
        applyVotes(canonical: votesByKey, pollsByID: pollsByID, localMemberID: localMemberID, memberKey: memberKey, context: context)

        // 11. Reconcile RSVPs per meeting (one canonical RSVP per (meeting, member)).
        applyRSVPs(canonical: rsvpsByKey, meetingsByID: meetingsByID, localMemberID: localMemberID, memberKey: memberKey, context: context)

        // 12. Notification events (only after we have a baseline snapshot —
        //     never on first import or we'd flood the user).
        let notificationEvents: [BookLoomNotificationEvent]
        if let baseline = club.lastSharedSnapshotAt {
            notificationEvents = BookLoomNotificationEvent.events(
                clubName: club.name,
                previousSubmissions: preMergeSubmissions,
                previousPromptIDs: preMergePromptIDs,
                previousPollIDs: preMergePollIDs,
                previousMeetingIDs: preMergeMeetingIDs,
                canonicalSubmissions: Array(canonicalSubmissions.values),
                canonicalStatusOverrides: statusOverridesByID.values.flatMap { $0 },
                canonicalRatings: Array(ratingsByKey.values),
                canonicalNotes: Array(notesByKey.values),
                canonicalPrompts: Array(canonicalPrompts.values),
                canonicalPolls: Array(canonicalPolls.values),
                canonicalMeetings: Array(canonicalMeetings.values),
                localMemberID: localMemberID,
                sinceCapturedAt: baseline
            )
        } else {
            notificationEvents = []
        }

        let latestCaptureAt = activeSnapshots.map(\.capturedAt).max() ?? .now
        club.lastSharedSnapshotAt = latestCaptureAt

        let activePersonKeys = Set(activeSnapshots.map { memberKey($0.authorMemberID) })
        var roster = club.knownMemberRoster.filter { memberID, _ in
            !removedPersonKeys.contains(memberKey(memberID)) && activePersonKeys.contains(memberKey(memberID))
        }
        for snap in activeSnapshots {
            let trimmedID = snap.authorMemberID.trimmedOrNil
            let trimmedName = snap.authorName.trimmedOrNil
            guard let id = trimmedID, let name = trimmedName else { continue }
            roster[id] = name
        }
        club.knownMemberRoster = roster

        // Once a status override has appeared in a remote snapshot, we no
        // longer need to keep echoing it from local cache.
        let allOverrides = statusOverridesByID.values.flatMap { $0 }
        club.pruneAcknowledgedStatusOverrides(merged: allOverrides)
        let allDetailsOverrides = detailsOverridesByID.values.flatMap { $0 }
        club.pruneAcknowledgedSubmissionDetailsOverrides(merged: allDetailsOverrides)
        let allDeletions = deletionsByID.values.flatMap { $0 }
        club.pruneAcknowledgedSubmissionDeletions(merged: allDeletions)

        try context.save()

        if !notificationEvents.isEmpty {
            Task {
                await BookLoomUserNotifications.schedule(notificationEvents)
            }
        }
    }

    // MARK: - Merge helpers

    private static func clubMetaVersion(_ snapshot: MemberShareSnapshot) -> Date {
        guard let meta = snapshot.clubMeta else { return .distantPast }
        return meta.metadataUpdatedAt ?? snapshot.capturedAt
    }

    /// Reconcile a per-parent collection (ratings on submissions, votes on
    /// polls, RSVPs on meetings, etc.) against the canonical payloads. The
    /// generic version pre-builds an index of existing rows keyed by
    /// `existingKey` so the upsert is O(canonical + existing) rather than
    /// quadratic.
    private static func reconcileCollection<Parent, Existing: PersistentModel, Payload>(
        parents: some Collection<Parent>,
        canonical: [String: Payload],
        parentKey: (Parent) -> String,
        canonicalParentKey: (Payload) -> String,
        existingChildren: (Parent) -> [Existing],
        existingKey: (Existing) -> String,
        existingMemberID: (Existing) -> String,
        canonicalKey: (Payload) -> String,
        canonicalMemberID: (Payload) -> String,
        localMemberID: String,
        memberKey: (String) -> String,
        context: ModelContext,
        update: (Existing, Payload, String) -> Void,
        insert: (Parent, Payload, String) -> Void
    ) {
        var canonicalByParent: [String: [Payload]] = [:]
        for payload in canonical.values {
            canonicalByParent[canonicalParentKey(payload), default: []].append(payload)
        }
        let localPersonKey = memberKey(localMemberID)
        for parent in parents {
            let canonicalForParent = canonicalByParent[parentKey(parent)] ?? []
            let canonicalByKey = Dictionary(
                canonicalForParent.map { (canonicalKey($0), $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            let existing = existingChildren(parent)
            let existingByKey = Dictionary(grouping: existing, by: existingKey)

            for (key, duplicates) in existingByKey {
                let keeper = duplicates.first(where: { existingMemberID($0) == localMemberID })
                    ?? duplicates.last!
                for duplicate in duplicates where duplicate.persistentModelID != keeper.persistentModelID {
                    context.delete(duplicate)
                }

                guard let payload = canonicalByKey[key] else {
                    if existingMemberID(keeper) != localMemberID {
                        context.delete(keeper)
                    }
                    continue
                }
                let payloadMemberID = canonicalMemberID(payload)
                let storedMemberID = memberKey(payloadMemberID) == localPersonKey
                    ? localMemberID
                    : payloadMemberID
                if payloadMemberID == localMemberID,
                   existingMemberID(keeper) == localMemberID {
                    continue
                }
                update(keeper, payload, storedMemberID)
            }

            for payload in canonicalForParent where existingByKey[canonicalKey(payload)] == nil {
                let payloadMemberID = canonicalMemberID(payload)
                let storedMemberID = memberKey(payloadMemberID) == localPersonKey
                    ? localMemberID
                    : payloadMemberID
                insert(parent, payload, storedMemberID)
            }
        }
    }

    private static func applyRatings(
        canonical: [String: MemberShareSnapshot.RatingPayload],
        submissionsByID: [String: BookSubmission],
        localMemberID: String,
        memberKey: @escaping (String) -> String,
        context: ModelContext
    ) {
        reconcileCollection(
            parents: submissionsByID.values,
            canonical: canonical,
            parentKey: \.selectionID,
            canonicalParentKey: \.submissionSelectionID,
            existingChildren: { $0.ratings ?? [] },
            existingKey: { memberKey($0.memberID) },
            existingMemberID: \.memberID,
            canonicalKey: { memberKey($0.memberID) },
            canonicalMemberID: \.memberID,
            localMemberID: localMemberID,
            memberKey: memberKey,
            context: context,
            update: { rating, payload, storedMemberID in
                rating.memberID = storedMemberID
                rating.memberName = payload.memberName
                rating.stars = payload.stars
                rating.createdAt = payload.createdAt
            },
            insert: { submission, payload, storedMemberID in
                let rating = Rating(
                    memberID: storedMemberID,
                    memberName: payload.memberName,
                    stars: payload.stars,
                    createdAt: payload.createdAt
                )
                rating.submission = submission
                context.insert(rating)
                var ratings = submission.ratings ?? []
                ratings.append(rating)
                submission.ratings = ratings
            }
        )
    }

    private static func applyNotes(
        canonical: [String: MemberShareSnapshot.NotePayload],
        submissionsByID: [String: BookSubmission],
        localMemberID: String,
        memberKey: @escaping (String) -> String,
        context: ModelContext
    ) {
        // Notes are keyed by (memberID, createdAt) so multiple notes per
        // member per submission are preserved.
        let noteKey: (String, Date) -> String = { "\($0)|\($1.timeIntervalSince1970)" }
        reconcileCollection(
            parents: submissionsByID.values,
            canonical: canonical,
            parentKey: \.selectionID,
            canonicalParentKey: \.submissionSelectionID,
            existingChildren: { $0.notes ?? [] },
            existingKey: { noteKey(memberKey($0.memberID), $0.createdAt) },
            existingMemberID: \.memberID,
            canonicalKey: { noteKey(memberKey($0.memberID), $0.createdAt) },
            canonicalMemberID: \.memberID,
            localMemberID: localMemberID,
            memberKey: memberKey,
            context: context,
            update: { note, payload, storedMemberID in
                note.memberID = storedMemberID
                note.memberName = payload.memberName
                note.text = payload.text
            },
            insert: { submission, payload, storedMemberID in
                let note = BookNote(
                    memberID: storedMemberID,
                    memberName: payload.memberName,
                    text: payload.text,
                    createdAt: payload.createdAt
                )
                note.submission = submission
                context.insert(note)
                var notes = submission.notes ?? []
                notes.append(note)
                submission.notes = notes
            }
        )
    }

    private static func applyVotes(
        canonical: [String: MemberShareSnapshot.VotePayload],
        pollsByID: [String: SelectionPoll],
        localMemberID: String,
        memberKey: @escaping (String) -> String,
        context: ModelContext
    ) {
        reconcileCollection(
            parents: pollsByID.values,
            canonical: canonical,
            parentKey: \.pollID,
            canonicalParentKey: \.pollID,
            existingChildren: { $0.votes ?? [] },
            existingKey: { memberKey($0.memberID) },
            existingMemberID: \.memberID,
            canonicalKey: { memberKey($0.memberID) },
            canonicalMemberID: \.memberID,
            localMemberID: localMemberID,
            memberKey: memberKey,
            context: context,
            update: { vote, payload, storedMemberID in
                vote.memberID = storedMemberID
                vote.memberName = payload.memberName
                vote.rankedSubmissionIDsRaw = payload.rankedSubmissionIDsRaw
                vote.updatedAt = payload.updatedAt
            },
            insert: { poll, payload, storedMemberID in
                let vote = BookVote(
                    memberID: storedMemberID,
                    memberName: payload.memberName,
                    rankedSubmissionIDs: SelectionPoll.decodeIDs(payload.rankedSubmissionIDsRaw),
                    updatedAt: payload.updatedAt
                )
                vote.poll = poll
                context.insert(vote)
                var votes = poll.votes ?? []
                votes.append(vote)
                poll.votes = votes
            }
        )
    }

    private static func applyRSVPs(
        canonical: [String: MemberShareSnapshot.RSVPPayload],
        meetingsByID: [String: ClubMeeting],
        localMemberID: String,
        memberKey: @escaping (String) -> String,
        context: ModelContext
    ) {
        reconcileCollection(
            parents: meetingsByID.values,
            canonical: canonical,
            parentKey: \.meetingID,
            canonicalParentKey: \.meetingID,
            existingChildren: { $0.rsvps ?? [] },
            existingKey: { memberKey($0.memberID) },
            existingMemberID: \.memberID,
            canonicalKey: { memberKey($0.memberID) },
            canonicalMemberID: \.memberID,
            localMemberID: localMemberID,
            memberKey: memberKey,
            context: context,
            update: { rsvp, payload, storedMemberID in
                rsvp.memberID = storedMemberID
                rsvp.memberName = payload.memberName
                rsvp.statusRaw = payload.statusRaw
                rsvp.bringingNote = payload.bringingNote
                rsvp.updatedAt = payload.updatedAt
            },
            insert: { meeting, payload, storedMemberID in
                let rsvp = MeetingRSVP(
                    memberID: storedMemberID,
                    memberName: payload.memberName,
                    status: MeetingRSVPStatus(rawValue: payload.statusRaw) ?? .attending,
                    bringingNote: payload.bringingNote,
                    updatedAt: payload.updatedAt
                )
                rsvp.meeting = meeting
                context.insert(rsvp)
                var rsvps = meeting.rsvps ?? []
                rsvps.append(rsvp)
                meeting.rsvps = rsvps
            }
        )
    }
}
