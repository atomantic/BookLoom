# PlotLoom

Book club companion for picking, tracking, rating, and noting your group's reads — like a potluck where everyone brings a book and the loom weaves the picks together.

iOS + macOS, SwiftUI + SwiftData, synced via iCloud.

## Status

Early scaffold (v0.1). Core flows implemented:

- Local member identity (your display name, stored in UserDefaults)
- Create a book club
- Submit books to the proposal pool
- Random picker — promotes a proposed book to "currently reading" and archives the previous one
- Per-member 1–5 star ratings
- Per-member notes per book

Not yet implemented (see `PLAN.md`):

- iCloud invite path (CKShare-based group sharing)
- Cover image fetch from ISBN
- Reading deadlines / meeting dates
- Export / import club history

## Develop

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open PlotLoom.xcodeproj
```

The project file is generated from `project.yml` and is git-ignored. Re-run `xcodegen generate` after editing `project.yml`.

## Test

```sh
xcodebuild test -project PlotLoom.xcodeproj -scheme PlotLoom_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' | xcbeautify
```

## Deploy to TestFlight

GitHub Actions only builds and tests — TestFlight uploads happen locally via `deploy.sh`.

1. Copy `.env.example` to `.env` and fill in your App Store Connect API key details (path to `.p8` file, key ID, issuer ID).
2. Make sure your distribution cert is in your keychain (run a one-time `Product → Archive` in Xcode if not).
3. Run:

```sh
./deploy.sh                # builds and uploads iOS + macOS
./deploy.sh --ios          # iOS only
./deploy.sh --macos        # macOS only
./deploy.sh --skip-tests   # skip test step
```

The script auto-bumps `CURRENT_PROJECT_VERSION` in `project.yml`, regenerates the Xcode project, archives, exports, re-signs the iOS IPA with explicit CloudKit entitlements, and uploads via `altool`. Build number bump is rolled back automatically if any step fails.

## License

Personal project — no license granted.
