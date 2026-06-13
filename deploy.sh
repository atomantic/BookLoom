#!/bin/bash
set -euo pipefail

# BookLoom — Local TestFlight Deploy
#
# Usage: ./deploy.sh [--skip-tests] [--ios] [--macos] [--all]
#
#   Default (no platform flag): both iOS and macOS.
#   --ios / --macos : single platform.
#   --all           : explicit "both" (same as default).
#
# Uploads are serial with a 60s gap between each to avoid Apple's CDN
# rejecting concurrent uploads from the same API key.
#
# Requires .env (see .env.example) and an active App Store Connect API key.
# Build number is auto-incremented in project.yml; XcodeGen regenerates the
# Xcode project before each build.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "❌ .env file not found. Copy .env.example to .env and fill in values."
    exit 1
fi

# Expand ~ in the key path.
KEY_PATH="${APPSTORE_API_PRIVATE_KEY_PATH/#\~/$HOME}"
if [ ! -f "$KEY_PATH" ]; then
    echo "❌ API key not found at: $KEY_PATH"
    exit 1
fi

# The App Store Connect private key uploads builds — it should not live in a
# cloud-synced folder where it propagates to every signed-in device. Warn if it does.
case "$KEY_PATH" in
    *"Mobile Documents"*|*"CloudDocs"*|*"Dropbox"*|*"Google Drive"*|*"OneDrive"*)
        echo "⚠️  API key is in a cloud-synced folder ($KEY_PATH)."
        echo "    Move it to a local-only path (e.g. ~/.private_keys/) and update APPSTORE_API_PRIVATE_KEY_PATH in .env."
        ;;
esac

# altool only looks in ~/.private_keys/ for the API key — symlink it in.
mkdir -p ~/.private_keys
KEY_FILENAME="AuthKey_${APPSTORE_API_KEY_ID}.p8"
if [ ! -f ~/.private_keys/"$KEY_FILENAME" ]; then
    ln -sf "$KEY_PATH" ~/.private_keys/"$KEY_FILENAME"
    echo "🔑 Symlinked API key to ~/.private_keys/"
fi

PROJECT="BookLoom.xcodeproj"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="BookLoom"
SCHEME_IOS="BookLoom_iOS"
SCHEME_MACOS="BookLoom_macOS"
TEST_BUNDLE_IOS="BookLoomTests_iOS"
IOS_BUNDLE_ID="net.shadowpuppet.PlotLoom"
ICLOUD_CONTAINER="iCloud.${IOS_BUNDLE_ID}"
APP_GROUP_ID="group.net.shadowpuppet.PlotLoom"

SKIP_TESTS=false
EXPLICIT_IOS=false
EXPLICIT_MACOS=false
FAN_OUT=false
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=true ;;
        --ios)        EXPLICIT_IOS=true ;;
        --macos)      EXPLICIT_MACOS=true ;;
        --all)        FAN_OUT=true ;;
    esac
done

BUILD_IOS=false
BUILD_MACOS=false
if ! $EXPLICIT_IOS && ! $EXPLICIT_MACOS && ! $FAN_OUT; then
    FAN_OUT=true
fi
if $FAN_OUT;        then BUILD_IOS=true; BUILD_MACOS=true; fi
if $EXPLICIT_IOS;   then BUILD_IOS=true; fi
if $EXPLICIT_MACOS; then BUILD_MACOS=true; fi

MSG="🎯 Deploying to:"
$BUILD_IOS   && MSG="$MSG iOS"
$BUILD_MACOS && MSG="$MSG macOS"
echo "$MSG"

# Auto-bump build number in project.yml (XcodeGen rewrites .xcodeproj on every
# generate, so the .yml is the source of truth). Snapshot first so we can roll
# back on failure.
ORIG_PROJECT_YML=$(mktemp)
cp project.yml "$ORIG_PROJECT_YML"

# Query App Store Connect for the highest existing build number for $1
# (bundle ID). Echos the integer, or 0 on any failure so the caller can
# fall back to the local project.yml value. ES256 JWT signed via openssl
# + Python stdlib — no pip deps.
fetch_remote_build() {
    BUNDLE_ID="$1" KEY_ID="$APPSTORE_API_KEY_ID" \
    ISSUER="$APPSTORE_ISSUER_ID" KEY_PATH_ENV="$KEY_PATH" \
    python3 - <<'PYEOF' 2>/dev/null || echo 0
import os, sys, json, time, base64, subprocess, urllib.request

def fail(): print(0); sys.exit(0)

try:
    key_id   = os.environ['KEY_ID']
    issuer   = os.environ['ISSUER']
    key_path = os.environ['KEY_PATH_ENV']
    bundle   = os.environ['BUNDLE_ID']

    def b64url(d): return base64.urlsafe_b64encode(d).rstrip(b'=')

    now = int(time.time())
    header = b64url(json.dumps({'alg':'ES256','kid':key_id,'typ':'JWT'}, separators=(',',':')).encode())
    claims = b64url(json.dumps({'iss':issuer,'iat':now,'exp':now+1200,'aud':'appstoreconnect-v1'}, separators=(',',':')).encode())
    signing_input = header + b'.' + claims

    der = subprocess.run(
        ['openssl','dgst','-sha256','-sign',key_path],
        input=signing_input, capture_output=True, check=True
    ).stdout

    # DER ECDSA sig -> JOSE raw r||s (32 bytes each).
    if der[0] != 0x30: fail()
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    rl = der[i+1]; r = der[i+2:i+2+rl]; i += 2 + rl
    sl = der[i+1]; s = der[i+2:i+2+sl]
    r = r.lstrip(b'\x00').rjust(32, b'\x00')
    s = s.lstrip(b'\x00').rjust(32, b'\x00')
    token = (signing_input + b'.' + b64url(r + s)).decode()

    def get(url):
        req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
        return json.loads(urllib.request.urlopen(req, timeout=20).read())

    apps = get(f'https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]={bundle}').get('data', [])
    if not apps: fail()
    builds = get(
        f'https://api.appstoreconnect.apple.com/v1/builds?filter[app]={apps[0]["id"]}'
        '&sort=-uploadedDate&limit=200'
    ).get('data', [])
    versions = [int(b['attributes']['version']) for b in builds
                if b.get('attributes', {}).get('version', '').isdigit()]
    print(max(versions) if versions else 0)
except Exception:
    fail()
PYEOF
}

LOCAL_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')
echo "🔍 Checking TestFlight for highest existing build..."
REMOTE_BUILD=$(fetch_remote_build "$IOS_BUNDLE_ID")
REMOTE_BUILD=${REMOTE_BUILD:-0}
if [ "$REMOTE_BUILD" -gt "$LOCAL_BUILD" ]; then
    echo "ℹ️  TestFlight has build $REMOTE_BUILD; project.yml only at $LOCAL_BUILD — using remote as base."
    CURRENT_BUILD=$REMOTE_BUILD
else
    CURRENT_BUILD=$LOCAL_BUILD
fi
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "📦 Build number: $CURRENT_BUILD → $NEW_BUILD"
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: ${LOCAL_BUILD}/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" project.yml

DEPLOY_SUCCESS=false
rollback_build_bump() {
    if [ "$DEPLOY_SUCCESS" = "false" ]; then
        echo "↩️  Rolling back build number bump (deploy did not complete)..."
        cp "$ORIG_PROJECT_YML" project.yml 2>/dev/null || true
        xcodegen generate >/dev/null 2>&1 || true
    fi
    rm -f "$ORIG_PROJECT_YML"
}
trap rollback_build_bump EXIT

echo "⚙️  Regenerating Xcode project..."
xcodegen generate >/dev/null

if ! $SKIP_TESTS; then
    echo "🧪 Running tests..."
    DESTINATION=$(
        SIMINFO=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
preferred = ['iPhone 17 Pro', 'iPhone 17', 'iPhone 16 Pro', 'iPhone 16', 'iPhone 15']
def runtime_key(rt):
    parts = rt.replace('com.apple.CoreSimulator.SimRuntime.iOS-', '').split('-')
    try: return tuple(int(p) for p in parts)
    except: return (0,)
runtimes = sorted((rt for rt in data.get('devices', {}) if 'iOS' in rt), key=runtime_key, reverse=True)
for name in preferred:
    for rt in runtimes:
        for d in data['devices'][rt]:
            if d.get('isAvailable') and d.get('name') == name:
                print(f\"{d['name']},{d['udid']}\"); sys.exit(0)
for rt in runtimes:
    for d in data['devices'][rt]:
        if d.get('isAvailable') and 'iPhone' in d.get('name', ''):
            print(f\"{d['name']},{d['udid']}\"); sys.exit(0)
" 2>/dev/null)
        SIM_NAME="${SIMINFO%%,*}"
        SIM_UDID="${SIMINFO##*,}"
        if [ -n "$SIM_UDID" ]; then
            echo "📱 Test device: $SIM_NAME ($SIM_UDID)" >&2
            echo "platform=iOS Simulator,id=$SIM_UDID"
        else
            echo "platform=iOS Simulator,name=iPhone 16"
        fi
    )
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME_IOS" \
        -only-testing:"$TEST_BUNDLE_IOS" \
        -destination "$DESTINATION" \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=NO \
        -quiet
    echo "✅ Tests passed"
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

EXPORT_PLIST="$BUILD_DIR/exportOptions.plist"
cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

# altool exits 0 even when uploads fail — grep the log for definitive failures.
# Do NOT grep plain "ERROR:" — altool logs transient retry events that recover.
FAIL_MARKERS="UPLOAD FAILED|Validation failed \(|ERROR ITMS-|product-errors"

UPLOADED_ONE=false
inter_upload_delay() {
    if $UPLOADED_ONE; then
        echo "⏳ Waiting 60s before next upload to avoid Apple CDN contention..."
        sleep 60
    fi
}

# --- iOS ---
if $BUILD_IOS; then
    ARCHIVE_IOS="$BUILD_DIR/${APP_NAME}_iOS.xcarchive"
    EXPORT_IOS="$BUILD_DIR/export_ios"

    echo "📦 Archiving iOS..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME_IOS" \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE_IOS" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet
    echo "✅ iOS archive complete"

    echo "📤 Exporting iOS IPA..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_IOS" \
        -exportOptionsPlist "$EXPORT_PLIST" \
        -exportPath "$EXPORT_IOS" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet

    IPA_PATH="$EXPORT_IOS/${APP_NAME}.ipa"
    if [ ! -f "$IPA_PATH" ]; then
        echo "❌ iOS IPA not found at $IPA_PATH"
        ls -la "$EXPORT_IOS/"
        exit 1
    fi

    VERIFY_DIR="$BUILD_DIR/verify_ios"
    rm -rf "$VERIFY_DIR" && mkdir -p "$VERIFY_DIR"
    unzip -q "$IPA_PATH" -d "$VERIFY_DIR"
    VERIFY_APP="$VERIFY_DIR/Payload/${APP_NAME}.app"
    VERIFY_SHARE_EXTENSION="$VERIFY_APP/PlugIns/BookLoomShareExtension.appex"
    if [ ! -d "$VERIFY_SHARE_EXTENSION" ]; then
        echo "❌ Share extension not found at $VERIFY_SHARE_EXTENSION"
        exit 1
    fi

    if ! codesign -d --entitlements :- "$VERIFY_APP" 2>/dev/null \
        | grep -q "com.apple.developer.icloud-container-identifiers"; then
        echo "❌ Exported IPA is missing CloudKit entitlements in the iOS app — aborting"
        codesign -d --entitlements :- "$VERIFY_APP" 2>&1 | head
        exit 1
    fi
    if ! codesign -d --entitlements :- "$VERIFY_APP" 2>/dev/null \
        | grep -q "$ICLOUD_CONTAINER"; then
        echo "❌ Exported IPA is missing the production CloudKit container in the iOS app — aborting"
        codesign -d --entitlements :- "$VERIFY_APP" 2>&1 | head
        exit 1
    fi
    if ! codesign -d --entitlements :- "$VERIFY_APP" 2>/dev/null \
        | grep -q "$APP_GROUP_ID"; then
        echo "❌ Exported IPA is missing App Group entitlements in the iOS app — aborting"
        codesign -d --entitlements :- "$VERIFY_APP" 2>&1 | head
        exit 1
    fi
    if ! codesign -d --entitlements :- "$VERIFY_SHARE_EXTENSION" 2>/dev/null \
        | grep -q "$APP_GROUP_ID"; then
        echo "❌ Exported IPA is missing App Group entitlements in the share extension — aborting"
        codesign -d --entitlements :- "$VERIFY_SHARE_EXTENSION" 2>&1 | head
        exit 1
    fi
    if ! security cms -D -i "$VERIFY_APP/embedded.mobileprovision" 2>/dev/null \
        | grep -q "$APP_GROUP_ID"; then
        echo "❌ Exported IPA provisioning profile is missing App Group entitlements in the iOS app — aborting"
        exit 1
    fi
    if ! security cms -D -i "$VERIFY_SHARE_EXTENSION/embedded.mobileprovision" 2>/dev/null \
        | grep -q "$APP_GROUP_ID"; then
        echo "❌ Exported IPA provisioning profile is missing App Group entitlements in the share extension — aborting"
        exit 1
    fi
    echo "✅ Exported iOS IPA; CloudKit and App Group entitlements verified in signatures and profiles"

    inter_upload_delay
    echo "🚀 Uploading iOS to TestFlight..."
    IOS_UPLOAD_LOG="$BUILD_DIR/ios_upload.log"
    set +e
    xcrun altool --upload-app \
        --file "$IPA_PATH" \
        --apiKey "$APPSTORE_API_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID" 2>&1 | tee "$IOS_UPLOAD_LOG"
    IOS_UPLOAD_STATUS=${PIPESTATUS[0]}
    set -e
    if [ "$IOS_UPLOAD_STATUS" -ne 0 ] || grep -qE "$FAIL_MARKERS" "$IOS_UPLOAD_LOG"; then
        echo "❌ iOS upload failed — see errors above"
        exit 1
    fi
    echo "✅ iOS upload complete!"
    UPLOADED_ONE=true
fi

# --- macOS ---
if $BUILD_MACOS; then
    ARCHIVE_MACOS="$BUILD_DIR/${APP_NAME}_macOS.xcarchive"
    EXPORT_MACOS="$BUILD_DIR/export_macos"

    echo "📦 Archiving macOS..."
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME_MACOS" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_MACOS" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet
    echo "✅ macOS archive complete"

    echo "📤 Exporting macOS pkg..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_MACOS" \
        -exportOptionsPlist "$EXPORT_PLIST" \
        -exportPath "$EXPORT_MACOS" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$APPSTORE_API_KEY_ID" \
        -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID" \
        -quiet

    PKG_PATH=$(find "$EXPORT_MACOS" -name "*.pkg" | head -1)
    if [ -z "$PKG_PATH" ]; then
        echo "❌ macOS package not found in $EXPORT_MACOS"
        ls -la "$EXPORT_MACOS/"
        exit 1
    fi

    inter_upload_delay
    echo "🚀 Uploading macOS to TestFlight..."
    MACOS_UPLOAD_LOG="$BUILD_DIR/macos_upload.log"
    set +e
    xcrun altool --upload-package "$PKG_PATH" \
        --apiKey "$APPSTORE_API_KEY_ID" \
        --apiIssuer "$APPSTORE_ISSUER_ID" 2>&1 | tee "$MACOS_UPLOAD_LOG"
    MACOS_UPLOAD_STATUS=${PIPESTATUS[0]}
    set -e
    if [ "$MACOS_UPLOAD_STATUS" -ne 0 ] || grep -qE "$FAIL_MARKERS" "$MACOS_UPLOAD_LOG"; then
        echo "❌ macOS upload failed — see errors above"
        exit 1
    fi
    echo "✅ macOS upload complete!"
    UPLOADED_ONE=true
fi

DEPLOY_SUCCESS=true
echo ""
echo "🎉 Deploy complete! Build $NEW_BUILD uploaded to TestFlight."
echo "   Processing usually takes 5-15 minutes before the build appears."
