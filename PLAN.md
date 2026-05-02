# PlotLoom Plan

## Done

- [x] Apple Developer: register `net.shadowpuppet.PlotLoom` Bundle ID
- [x] App Store Connect: register `PlotLoom` app (App ID `6765790616`, iOS + macOS)
- [x] Project scaffold: XcodeGen `project.yml`, entitlements (iOS + macOS sandbox), assets, Info.plist
- [x] SwiftData models: `BookClub`, `BookSubmission`, `Rating`, `BookNote`
- [x] CloudKit sync via `ModelConfiguration(cloudKitDatabase: .automatic)`
- [x] Local member identity (display name in UserDefaults)
- [x] Views: onboarding, create club, club home, add submission, submission detail with ratings + notes
- [x] Book picker (random pick from proposed → current; archives previous current to completed)
- [x] CI workflow: build + test on PR / push to main (no deploy — TestFlight via local `deploy.sh`)
- [x] `deploy.sh` for local TestFlight upload (iOS + macOS)
- [x] Initial git commit + private GitHub repo

## v0.2 — group sharing (code complete, awaiting portal setup)

- [x] CKShare-based book club sharing skeleton (cross-Apple-ID invite + accept flow)
  - `CloudKitSharingService` — atomic root+share save, accept handler
  - `UICloudSharingController` wrapper (iOS) — `CloudSharingControllerView`
  - macOS share-URL copy UX (NSPasteboard)
  - `ShareAcceptance` magic-string handler (`com.apple.CloudKit.ShareMetadata`)
  - SceneDelegate (iOS) + AppDelegate (macOS) cold-launch fallback via `AcceptedShareInbox`
  - `BookClub` extended with `cloudZoneName`, `ownerUserRecordName`, `shareIsActive`, `shareParticipantCount`
- [x] Invite UI in club home, gated by `Features.cloudKitSharing`
- [x] developer.apple.com → App ID `net.shadowpuppet.PlotLoom` → iCloud capability enabled, container `iCloud.net.shadowpuppet.PlotLoom` registered and assigned
- [ ] **Schema seed (blocked on running app once)**:
  1. Flip `Features.cloudKitSharing = true` locally
  2. Run app in Xcode (Debug, simulator or device signed into iCloud)
  3. Create a club, tap Invite Members → CloudKit auto-creates the `BookClubShareRoot` record type in the Development schema
  4. icloud.developer.apple.com → open `iCloud.net.shadowpuppet.PlotLoom` container → verify the record type appears under Development → click "Deploy Schema Changes…" to push to Production
  5. Re-archive (automatic signing refreshes the provisioning profile to include the new entitlement)
  6. Smoke-test on two different Apple IDs via TestFlight
- [ ] Flip `Features.cloudKitSharing = true` and smoke-test on two Apple IDs
- [ ] Member list view (CKShare participants → display names)
- [ ] Sync status indicator in toolbar

## v0.3 — book metadata

- [ ] OpenLibrary / Google Books lookup by ISBN
- [ ] Cover thumbnail in submission row
- [ ] Manual cover image upload as fallback

## v0.4 — meeting & deadlines

- [ ] Meeting date per "current" book
- [ ] Reading reminders (local notifications)
- [ ] Past meetings log

## v1.0 — submission

- [ ] App Store screenshots (XCUITest automation, iOS + macOS)
- [ ] Privacy policy + terms (shadowpuppet.net subdomain)
- [ ] Marketing copy + subtitle
- [ ] App Store submission

## Notes

- Use existing Claudeception skills when implementing:
  - `swiftdata-cloudkit-cross-appleid-sharing` — household sharing
  - `cloudkit-sharing-first-time-implementation-gotchas` — CKShare gotchas
  - `cloudkit-sharing-simulator-test` — testing CKShare without two devices
  - `xcodegen-macos-entitlements-sandbox-regression` — already applied (separate macOS entitlements)
  - `swiftdata-missing-inverse-relationship-crash` — already applied (explicit `@Relationship(... inverse:)`)
