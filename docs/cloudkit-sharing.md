# CloudKit Sharing Runbook

## Current State

- The app has the iCloud container entitlement for `iCloud.net.shadowpuppet.PlotLoom`.
- `CKSharingSupported` is generated into the built iOS and macOS `Info.plist` files from `project.yml`.
- `CloudKitSharingService` creates a `BookClubShareRoot` record in a custom zone, saves a `CKShare`, and returns the created share even on OS builds that omit the `CKShare` from `modifyRecords` save results.
- `InviteLoadError` maps common CloudKit auth and network failures into user-actionable states.

## Production Checklist

1. Install a signed TestFlight or Development build that contains `CKSharingSupported = true`.
2. Create a club and tap Invite Members once while signed into iCloud.
3. Open CloudKit Console for `iCloud.net.shadowpuppet.PlotLoom`.
4. Confirm the Development schema contains `BookClubShareRoot`.
5. Use Deploy Schema Changes to promote the schema to Production.
6. Re-archive after schema/capability changes so signing profiles are refreshed.
7. Smoke-test with two Apple IDs:
   - Owner creates a club and opens Invite Members.
   - Recipient accepts the invite from the share link.
   - Owner and recipient each add a proposal, rating, and note.
   - Both devices verify the same club data after relaunch.

## Important Validation Boundary

SwiftData `.automatic` CloudKit sync handles a person's private database sync. The current share service creates an inviteable CloudKit share root, but it does not manually move SwiftData's object graph into a shared zone. If the two-account smoke test shows that proposals, ratings, or notes do not propagate between participants, the next implementation step should be one of:

- migrate the persistence layer to Core Data with `NSPersistentCloudKitContainer` sharing APIs, or
- make the shared CloudKit zone the collaboration source of truth and sync app models to explicit `CKRecord` records under `BookClubShareRoot`.
