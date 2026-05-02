# CloudKit Sharing Runbook

## Current State

- The app has the iCloud container entitlement for `iCloud.net.shadowpuppet.PlotLoom`.
- `CKSharingSupported` is generated into the built iOS and macOS `Info.plist` files from `project.yml`.
- `CloudKitSharingService` creates a `BookClubShareRoot` record in a custom zone, saves a `CKShare`, and returns the created share even on OS builds that omit the `CKShare` from `modifyRecords` save results.
- The share root carries a versioned JSON `snapshotData` payload for the club graph. Accepted invites import the full club state instead of creating only a placeholder `BookClub`.
- Cover images are not stored in the share snapshot or SwiftData for new writes. Shared snapshots carry cover URLs, and `BookCoverCache` stores fetched image bytes in each device's local Caches directory.
- Shared clubs refresh from the share root on club list/home load and publish a new snapshot after proposals, ratings, notes, prompts, meetings, RSVPs, polls, votes, and winner promotion changes.
- `InviteLoadError` maps common CloudKit auth and network failures into user-actionable states.

## Production Checklist

1. Install a signed TestFlight or Development build that contains `CKSharingSupported = true`.
2. Create a club and tap Invite Members once while signed into iCloud.
3. Open CloudKit Console for `iCloud.net.shadowpuppet.PlotLoom`.
4. Confirm the Development schema contains `BookClubShareRoot` with `clubName`, `snapshotData`, and `snapshotUpdatedAt`.
5. Use Deploy Schema Changes to promote the schema to Production.
6. Re-archive after schema/capability changes so signing profiles are refreshed.
7. Smoke-test with two Apple IDs:
   - Owner creates a club and opens Invite Members.
   - Recipient accepts the invite from the share link.
   - Owner and recipient each add a proposal, rating, and note.
   - Both devices verify the same club data after relaunch.

## Important Validation Boundary

SwiftData `.automatic` CloudKit sync still handles a person's private database sync. Cross-account club collaboration now uses the CKShare root as a compact source of truth for v1, with last-writer-wins snapshot updates. This is intentionally simpler than per-object CloudKit records; the two-account TestFlight smoke test should verify:

- accepted invites show the real club name, current read, proposals, history, meetings, polls, ratings, notes, prompts, and locally cached cover images after onboarding;
- edits from both owner and recipient publish and refresh after navigating away/back or relaunching;
- concurrent edits do not corrupt the snapshot payload. Last writer wins is acceptable for v1, but data loss is not.
