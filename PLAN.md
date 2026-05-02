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

## Up next (v0.2 — group sharing)

- [ ] CKShare-based book club sharing (cross-Apple-ID invite + accept flow)
  - `UICloudSharingController` (iOS) / `NSSharingService` (macOS)
  - Generate share URL when starting a club
  - Accept share via universal link / `plotloom://` URL
  - Make `BookClub` the CKShare root entity (all submissions/ratings/notes in same shared zone)
  - See existing skill: `swiftdata-cloudkit-cross-appleid-sharing`
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
