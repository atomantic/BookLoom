# BookLoom Plan

## Done

- [x] Apple Developer: register `net.shadowpuppet.PlotLoom` Bundle ID
- [x] App Store Connect: register `BookLoom` app (App ID `6765790616`, iOS + macOS)
- [x] Project scaffold: XcodeGen `project.yml`, entitlements (iOS + macOS sandbox), assets, Info.plist
- [x] SwiftData models: `BookClub`, `BookSubmission`, `Rating`, `BookNote`
- [x] CloudKit sync via `ModelConfiguration(cloudKitDatabase: .automatic)`
- [x] Local member identity (display name in UserDefaults)
- [x] Views: onboarding, create club, club home, add submission, submission detail with ratings + notes
- [x] Book picker (random pick from proposed → current; archives previous current to completed)
- [x] CI workflow: build + test on PR / push to main (no deploy — TestFlight via local `deploy.sh`)
- [x] `deploy.sh` for local TestFlight upload (iOS + macOS)
- [x] Initial git commit + private GitHub repo

## v0.3 — Polished for TestFlight

- [x] Tabbed root: Clubs / Settings (replaces single-club hard route)
- [x] ClubsListView with empty state, swipe-to-delete, "+ New Club" toolbar
- [x] SettingsView: edit member name, version info, iCloud setup status
- [x] Swipe-to-delete on submissions (proposed and read sections)
- [x] "Mark Complete" swipe action on currently-reading book
- [x] Pick Random confirmation dialog (prevents accidental rotation)
- [x] User-actionable iCloud auth errors (Sign in / Turn on Drive / Network)
- [x] Removed unreferenced CreateOrJoinClubView (replaced by NewClubFormView sheet)
- [x] BookLoomDesign system: shared `String.trimmed`, `bookLoomListRow()`, `TintedCapsuleLabel`
- [x] Single-pass `BookClubMetrics` / `BookClubSubmissionSections` (was 5 filter passes)
- [x] Skip redundant CloudKit fetch when `saveResults` returns the share directly
- [x] Populate `AccentColor.colorset` with brand plum (matches `.tint` everywhere)

## v0.2 — group sharing (code complete, awaiting portal setup)

- [x] CKShare-based book club sharing skeleton (cross-Apple-ID invite + accept flow)
  - `CloudKitSharingService` — atomic root+share save, accept handler
  - `UICloudSharingController` wrapper (iOS) — `CloudSharingControllerView`
  - macOS share-URL copy UX (NSPasteboard)
  - `ShareAcceptance` magic-string handler (`com.apple.CloudKit.ShareMetadata`)
  - SceneDelegate (iOS) + AppDelegate (macOS) cold-launch fallback via `AcceptedShareInbox`
  - `BookClub` extended with `cloudZoneName`, `ownerUserRecordName`, `shareIsActive`, `shareParticipantCount`
- [x] Shared club snapshot sync for v1 collaboration
  - `BookClubShareRoot.snapshotData` stores a versioned JSON club graph
  - accepted invites import the real club, proposals, current read, history, meetings, polls, ratings, notes, prompts, and cover URLs for local cover caching
  - club mutations publish a new share-root snapshot; shared clubs refresh on list/home load
- [x] Invite UI in club home, gated by `Features.cloudKitSharing`
- [x] developer.apple.com → App ID `net.shadowpuppet.PlotLoom` → iCloud capability enabled, container `iCloud.net.shadowpuppet.PlotLoom` registered and assigned
- [ ] **Schema seed / deploy for share snapshot fields**:
  1. Confirm `Features.cloudKitSharing = true`
  2. Run app in Xcode (Debug, simulator or device signed into iCloud), or run the schema primer with `BOOKLOOM_PRIME_CLOUDKIT_SCHEMA=1`
  3. Create a club, tap Invite Members → CloudKit auto-creates the `BookClubShareRoot` record type in the Development schema
  4. icloud.developer.apple.com → open `iCloud.net.shadowpuppet.PlotLoom` container → verify `BookClubShareRoot` has `clubName`, `snapshotData`, and `snapshotUpdatedAt` → click "Deploy Schema Changes…" to push to Production
  5. Re-archive (automatic signing refreshes the provisioning profile to include the new entitlement)
  6. Smoke-test on two different Apple IDs via TestFlight
- [x] Flip `Features.cloudKitSharing = true`
- [ ] Smoke-test on two Apple IDs
- [x] Member list view (discovered member activity + share participant count)
- [x] Sync status indicator in toolbar

## v0.3 — book metadata

- [x] OpenLibrary + Google Books lookup with parallel detail enrichment (BookMetadataService)
- [x] Cover thumbnail in submission rows, current row, and detail hero (AsyncImage via `BookCoverTile.coverURL`)
- [x] Description + published year captured from external metadata
- [x] Local metadata search cache + cover image cache; cover bytes stay in the device Caches directory and are not written to SwiftData/iCloud for new submissions
- [ ] Manual cover image upload as fallback

## v0.3 — appearance & welcome

- [x] System / Light / Dark appearance toggle in Settings (`AppAppearance` AppStorage)
- [x] Adaptive design system colors and gradients for dark mode
- [x] "Relaunch Welcome" action in Settings to replay onboarding

## v0.3 — UX density and App Store readiness

- [x] Compact returning-user screens so valuable club, proposal, rating, and note content appears earlier
- [x] UX direction captured in `docs/ux-design-direction.md`
- [x] Screenshot sample data fixture for populated Clubs, Club Home, Submission Detail, Add Book, vote, and meeting states
- [ ] SwiftUI previews or screenshot fixtures for empty Clubs, Club Home, Submission Detail, and Add Book states

## v0.4 — meeting & deadlines

- [x] Meeting date per "current" book
- [x] Reading reminders (local notifications)
- [x] Past meetings log
- [x] Member list and sync status surface
- [x] Ranked selection polls with one ballot per member, tie display, and winner promotion
- [x] Reusable starter discussion prompts, custom prompts, meeting agenda, and Discussion Mode
- [x] App Store naming/subtitle recommendation captured in `docs/app-store-metadata.md`

## v1.0 — submission

- [x] App Store screenshot capture automation (XCUITest iOS + macOS script)
- [x] App Store screenshots uploaded for iPhone, iPad, and macOS
- [x] App Store Connect copy + marketing URL captured for iOS/macOS in `docs/app-store-metadata.md`
- [x] Publish marketing, support, privacy, and terms pages under `https://bookloom.shadowpuppet.net`
- [x] Enter App Store Connect metadata for iOS/macOS
- [x] App Store submission (previous iOS 1.0 and macOS 1.0 builds were submitted; next build should include the v1 club snapshot fix before release)

## Notes

- Use existing Claudeception skills when implementing:
  - `swiftdata-cloudkit-cross-appleid-sharing` — household sharing
  - `cloudkit-sharing-first-time-implementation-gotchas` — CKShare gotchas
  - `cloudkit-sharing-simulator-test` — testing CKShare without two devices
  - `xcodegen-macos-entitlements-sandbox-regression` — already applied (separate macOS entitlements)
  - `swiftdata-missing-inverse-relationship-crash` — already applied (explicit `@Relationship(... inverse:)`)
