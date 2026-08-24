# CloudKit Sharing Runbook

## Current State

- The app has the iCloud container entitlement for `iCloud.net.shadowpuppet.PlotLoom`.
- `CKSharingSupported` is generated into the built iOS and macOS `Info.plist` files from `project.yml`.
- `CloudKitSharingService` creates a `BookClubShareRoot` record in a custom zone, saves a `CKShare`, and returns the created share even on OS builds that omit the `CKShare` from `modifyRecords` save results.
- Each member snapshot is authenticated against CloudKit's immutable creator and latest-modifier system fields before merge. The owner publishes the canonical member-ID-to-CloudKit-user binding map in schema v4 `ClubMeta`.
- New shares are private, read/write collaborations. iOS and macOS use the system CloudKit sharing UI to add specified recipients; BookLoom no longer distributes a reusable public write link.
- Cover images are not stored in the share snapshot or SwiftData for new writes. Shared snapshots carry cover URLs, and `BookCoverCache` stores fetched image bytes in each device's local Caches directory.
- Shared clubs refresh from the share root on club list/home load and publish a new snapshot after proposals, ratings, notes, prompts, meetings, RSVPs, polls, votes, and winner promotion changes.
- `InviteLoadError` maps common CloudKit auth and network failures into user-actionable states.

## Production Checklist

1. Install a signed TestFlight or Development build that contains `CKSharingSupported = true`.
2. Create a club and tap Invite Members once while signed into iCloud.
3. Open CloudKit Console for `iCloud.net.shadowpuppet.PlotLoom`.
4. Confirm the Development schema contains `BookClubShareRoot` with `clubName` and `clubCreatedAt`, plus `MemberShareSnapshot` with `snapshotData`, `snapshotUpdatedAt`, `memberID`, and `memberName`.
5. Use Deploy Schema Changes to promote the schema to Production.
6. Re-archive after schema/capability changes so signing profiles are refreshed.
7. Smoke-test with two Apple IDs:
   - Owner creates a club and opens Invite Members.
   - Recipient accepts the invite from the share link.
   - Owner and recipient each add a proposal, rating, and note.
   - Both devices verify the same club data after relaunch.

## Authorization and legacy migration

- A snapshot record is accepted only when its record name matches its claimed `authorMemberID`, its CloudKit creator and latest modifier are the same user, and the owner-published binding maps that member ID to that CloudKit user.
- Every member-scoped identity inside the payload must match the authenticated snapshot author. Club metadata, the admin list, and removals are accepted only from the CloudKit share owner. Rename proposals additionally require the authenticated author to be the creator or an owner-designated admin.
- Status, details, and deletion overrides remain collaborative operations available to any verified member, but actor fields cannot impersonate another member.
- On an existing schema v1-v3 share, the provenance-verified owner snapshot is the trust root. When the owner next syncs, BookLoom enrolls intact legacy member records whose creator and latest modifier agree, then republishes the binding map. Other participants ignore unbound records until that owner migration arrives.
- Existing public shares are not converted silently. The owner sees an explicit migration screen explaining that public participants will be disconnected and need new specified-recipient invitations. Their already-published records remain in the owner's shared hierarchy.
- CloudKit removes public participants when a share's `publicPermission` changes to `.none`; this is why migration requires confirmation and re-invitation. New shares start at `.none` and never enter this legacy state.

## Important Validation Boundary

SwiftData `.automatic` CloudKit sync still handles a person's private database sync. Cross-account collaboration uses one authenticated `MemberShareSnapshot` record per member, tied to the CKShare root. Clients fetch the complete record set, reject the entire batch if provenance or owner trust is incomplete, and merge each member's self-attributed contributions by stable IDs and operation timestamps. The two-account TestFlight smoke test should verify:

- accepted invites show the real club name, current read, proposals, history, meetings, polls, ratings, notes, prompts, and locally cached cover images after onboarding;
- edits from both owner and recipient publish and refresh after navigating away/back or relaunching;
- concurrent edits from different members remain present after both clients refresh; competing operations on the same item resolve by their documented timestamps without corrupting or dropping unrelated contributions.
