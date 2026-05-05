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

## v1.x — Comparison-page gaps (from /vs/* SEO build, 2026-05-02)

Discovered while building marketing comparison pages at `bookloom.shadowpuppet.net/vs/{bookclubs,goodreads,fable,storygraph}/`. Each item is something at least one competitor ships that BookLoom does not, and where the gap measurably weakens the "BookLoom can replace X" pitch. Recommendations, not commitments — `/vs/*` pages already ship today with these cells marked "Planned" or "—" honestly.

- [ ] **Reading progress per member** (page or %) — Fable, StoryGraph, and Bookclubs all show this; without it our "currently reading" row is binary, which is the single biggest gap on the StoryGraph and Fable comparison pages. Smallest viable surface: a per-member progress slider (0/25/50/75/100 or page count) on the current submission, with optional CloudKit sync to the club share root.
- [ ] **Calendar export (.ics)** for scheduled meetings — Bookclubs gates this behind their $60/yr Premium; shipping it free strengthens the Bookclubs comparison and removes a regular friction point ("did anyone actually add this to their calendar?"). One-tap "Add to Calendar" share sheet that emits an `.ics` payload from `ClubMeeting` fields.
- [ ] **Threaded discussion on a book** (not just prompts) — Goodreads and Fable both ship this. Discussion Mode today is one-way (prompts surfaced for the meeting); a club may want async commentary between meetings. Could ride on top of the existing CKShare snapshot using a per-book comment thread.
- [ ] **Manual cover image upload as fallback** (already in PLAN above; bumped here because every comparison cell hits "no cover for self-published / obscure books" if ISBN lookup misses).
- [ ] **Export / import club history** (already in PLAN above; comparison pages explicitly call out "your data, exportable" as a BookLoom win — needs to actually exist before the messaging is honest).
- [ ] **Audiobook / Kindle / e-reader compatibility note** — no integration needed; just messaging on the marketing site (and possibly an in-app onboarding line) that BookLoom is format-agnostic. Some of the comparison-table rows around progress assume page-count tracking, which excludes audiobook listeners; explicit "any format works" copy fixes that.

## v1.2 — Personal Shelf on iOS/iPad

The macOS-style personal Shelf should come to iOS/iPad, but the mobile information architecture needs to keep two concepts separate: club reading records (`BookSubmission`: proposed/current/read by the group) and personal collection records (`LibraryBook`: books I own, borrowed, gifted, loaned, listened to, or want to track privately).

- [x] **Promote Shelf to iOS/iPad main navigation** — make personal Shelf a first-class top-level destination instead of a hidden route. The current club-scoped Books tab and club switcher are useful for group state, but personal shelf records are user-scoped and should not feel locked inside the active club.
- [x] **Rename the iOS/iPad Books tab to Club** — the current Books tab is really the active club workspace: proposals, current read, read history, Shelf imports, random pick, voting, meetings entry points, and the club switcher. Calling it "Club" makes room for "Shelf" to mean the user's personal collection.
- [x] **Demote Polls from top-level navigation** — remove Polls as a primary iOS tab unless testing shows users need it. Polls are a narrow tool for choosing the next book, so they should live in the Books workflow rather than compete with Shelf for main navigation.
- [x] **Fold voting into Books actions** — change the Books action row from Add Book / Pick Random into compact actions like "Add", "Random", and "Vote". "Vote" should create or open the active poll automatically from the current proposal pool instead of sending users to a separate poll-creation form.
- [x] **Show active poll state in the Books home** — surface the current voting state where users already look for the current-reading card: voting open, number of books/options, votes cast, and winner/next action. This keeps poll status tied to the book-selection workflow.
- [x] **Hide manual poll creation unless it proves necessary** — default to automatic poll creation from proposed books. If manual poll controls remain, put them behind an overflow/advanced affordance rather than making them a core screen.
- [x] **Keep Shelf import flow connected to the full Shelf** — the Shelf import area should still offer a path into the full Shelf viewer because users naturally arrive there after saving or importing books.
- [x] **Offer "keep on my Shelf" when adding a club book** — when a user adds a proposal/current/read book to a club, allow a toggle or checkbox to also save a `LibraryBook` copy. This should be explicit because club books and owned/borrowed/listened records track different real-world things.
- [x] **Offer "add to club" from personal Shelf** — from a `LibraryBook`, let the user add it to the active club as a proposal without losing or mutating the personal ownership record.
- [x] **Track read/listened format as personal state** — add a clear toggle/check/indicator for "I read this" and/or "I listened to the audiobook" when saving a book to the personal Shelf. This should be independent from the club's completed/read status, since a user may own a hardcover, borrow an ebook, or listen to the audiobook for the same club selection.
- [x] **Expose desktop Shelf fields on iOS/iPad** — iOS Shelf records can edit format, condition, shelf/room, signed copy, price, purchase source, loan, gift, private notes, read, and listened state.
- [x] **Scale Shelf for hundreds/thousands of books** — initial iOS Shelf uses lazy rows and batched SwiftData fetches so 300, 500, or 1000 scanned books do not need to render in one pass.
- [ ] **Push Shelf search/filter into SwiftData predicates** — the first iOS Shelf page batches record loading, but search/filter still applies to loaded records. Move search and filters into query predicates before large-shelf search is considered complete.
- [x] **Clarify record relationships** — avoid one shared mutable object for club and personal shelf. Prefer copy/link semantics: club submissions can reference external metadata/ISBN, while personal shelf entries keep ownership, format, loan, gift, purchase, read, and listened state.
- [x] **Rename pending imported books to Imports** — avoid showing two different "Shelf" sections. Pending Goodreads/shared/manual imports are a triage queue named "Imports"; permanent owned/borrowed/listened records stay in personal Shelf.
- [x] **Add import destination review** — imported books can be saved to the personal Shelf and added to one or more clubs from the same import sheet, with completed/read status available for club history.
- [ ] **Add multi-club destination picker from existing Shelf books** — existing Shelf detail still adds to the active club. Promote this to a destination picker so an owned book can be proposed to multiple clubs without re-importing.
- [x] **CloudKit schema follow-up** — Development schema was primed from the signed macOS debug app on 2026-05-05 for the new `LibraryBook` Shelf fields and CKShare records. Production was deployed from CloudKit Console on 2026-05-05, and the Production record types list now includes `CD_LibraryBook` with 37 fields.

## Future — monetization strategy (deferred)

Decision for now: keep BookLoom free while the basic app, sharing flows, and desktop/iPad shelf experience are still being flushed out. Do not add paywalls, premium service checks, or entitlement gates in the current v1.x work.

- [ ] **Protect the free core** — users should always be able to create and manage clubs, proposals, votes, meetings, personal shelf records, and their existing private data without a subscription.
- [ ] **Always allow data access and export** — because BookLoom stores private collection and club data, cancellation or lack of purchase must never lock users out of viewing, editing, deleting, or exporting their own records.
- [ ] **Prefer one-time Pro over subscription for local/private features** — if monetization is needed later, use a non-consumable "BookLoom Pro" unlock for advanced app features like the full desktop/iPad shelf workspace, smart shelves, custom tags, collection value summaries, richer export formats, barcode/metadata tools, and advanced loan/gift planning.
- [ ] **Reserve subscriptions for real ongoing costs** — only consider recurring pricing for services with continuing expenses, such as hosted web sharing, server-side notifications, AI recommendations/summaries, price tracking, or external metadata enrichment at scale.
- [ ] **No data hostage behavior** — if a subscription is ever added and later canceled, existing premium-created records remain visible/editable/exportable. Only future premium-only creation, automation, or hosted-service usage should stop.
- [ ] **Family-friendly pricing expectation** — if a Pro unlock ships, evaluate Family Sharing and a simple price point before adding multiple tiers.

## Notes

- Use existing Claudeception skills when implementing:
  - `swiftdata-cloudkit-cross-appleid-sharing` — household sharing
  - `cloudkit-sharing-first-time-implementation-gotchas` — CKShare gotchas
  - `cloudkit-sharing-simulator-test` — testing CKShare without two devices
  - `xcodegen-macos-entitlements-sandbox-regression` — already applied (separate macOS entitlements)
  - `swiftdata-missing-inverse-relationship-crash` — already applied (explicit `@Relationship(... inverse:)`)
