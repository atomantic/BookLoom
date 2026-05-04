#!/bin/bash
#
# take_screenshots.sh - Capture App Store screenshots for iPhone and iPad.
#
# Usage:
#   ./take_screenshots.sh
#   ./take_screenshots.sh --iphone-only
#   ./take_screenshots.sh --ipad-only
#   ./take_screenshots.sh --screen 01_clubs
#   ./take_screenshots.sh en
#

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/BookLoom.xcodeproj"
SCHEME="BookLoom_iOS"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"
CONFIG_FILE_PROJECT="$PROJECT_DIR/.screenshot_config.json"
CONFIG_FILE_TMP="/tmp/bookloom_screenshot_config.json"
DERIVED_DATA="$PROJECT_DIR/.build/DerivedData"

# Format: "Simulator Name|OS version|folder_name|test_method"
IPHONE_DEVICE="${BOOKLOOM_IPHONE_DEVICE:-iPhone 16 Pro Max}|${BOOKLOOM_IPHONE_OS:-18.6}|iphone_6.7|testCaptureIPhoneScreenshots"
IPAD_DEVICE="${BOOKLOOM_IPAD_DEVICE:-iPad Pro 13-inch (M4)}|${BOOKLOOM_IPAD_OS:-18.6}|ipad_13|testCaptureIPadScreenshots"

ALL_LANGUAGES=("en")

LANGUAGES=()
DEVICES=()
SCREEN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iphone-only) DEVICES=("$IPHONE_DEVICE"); shift ;;
        --ipad-only) DEVICES=("$IPAD_DEVICE"); shift ;;
        --screen) SCREEN="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--iphone-only|--ipad-only] [--screen <name>] [locale ...]"
            echo "Screens: 01_books 02_shelf 03_import 04_current_read 05_polls 06_vote 07_discussions 08_schedule 09_meeting 10_add_book"
            echo "Override devices with BOOKLOOM_IPHONE_DEVICE/BOOKLOOM_IPAD_DEVICE and BOOKLOOM_IPHONE_OS/BOOKLOOM_IPAD_OS."
            exit 0
            ;;
        *) LANGUAGES+=("$1"); shift ;;
    esac
done

[[ ${#LANGUAGES[@]} -eq 0 ]] && LANGUAGES=("${ALL_LANGUAGES[@]}")
[[ ${#DEVICES[@]} -eq 0 ]] && DEVICES=("$IPHONE_DEVICE" "$IPAD_DEVICE")

echo "=========================================="
echo "  BookLoom iOS Screenshot Capture"
echo "=========================================="
echo "  Languages: ${LANGUAGES[*]}"
echo "  Devices:   ${#DEVICES[@]}"
[[ -n "$SCREEN" ]] && echo "  Screen:    $SCREEN"
echo "  Output:    $SCREENSHOTS_DIR/{locale}/{device}/"
echo "=========================================="
echo ""

write_config() {
    local locale="$1"
    local device="$2"
    local output="$3"

    cat > "$CONFIG_FILE_PROJECT" <<JSONEOF
{
    "locale": "$locale",
    "device": "$device",
    "output_dir": "$output",
    "target_screen": "$SCREEN"
}
JSONEOF
    cp "$CONFIG_FILE_PROJECT" "$CONFIG_FILE_TMP" 2>/dev/null || true
}

destination_for() {
    local name="$1"
    local os="$2"
    if [[ -n "$os" ]]; then
        echo "platform=iOS Simulator,name=$name,OS=$os"
    else
        echo "platform=iOS Simulator,name=$name"
    fi
}

FAILED=()

for device_spec in "${DEVICES[@]}"; do
    IFS='|' read -r DEVICE_NAME DEVICE_OS DEVICE_FOLDER TEST_METHOD <<< "$device_spec"
    DESTINATION="$(destination_for "$DEVICE_NAME" "$DEVICE_OS")"

    echo "Building test bundle for $DEVICE_NAME..."
    xcodebuild build-for-testing \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO \
        -quiet
    echo "Build complete for $DEVICE_NAME"
    echo ""

    for LANG in "${LANGUAGES[@]}"; do
        echo "Capturing $LANG on $DEVICE_NAME..."
        write_config "$LANG" "$DEVICE_FOLDER" "$SCREENSHOTS_DIR"

        if xcodebuild test-without-building \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination "$DESTINATION" \
            -derivedDataPath "$DERIVED_DATA" \
            -only-testing:"BookLoomUITests_iOS/ScreenshotTests/$TEST_METHOD" \
            CODE_SIGNING_ALLOWED=NO \
            -quiet; then
            echo "  Complete: $LANG / $DEVICE_FOLDER"
        else
            echo "  Failed: $LANG / $DEVICE_FOLDER"
            FAILED+=("$LANG/$DEVICE_FOLDER")
        fi
    done
done

rm -f "$CONFIG_FILE_PROJECT" "$CONFIG_FILE_TMP"

echo ""
echo "=========================================="
echo "  Screenshot Capture Complete"
echo "=========================================="

for LANG in "${LANGUAGES[@]}"; do
    for device_spec in "${DEVICES[@]}"; do
        IFS='|' read -r _ _ DEVICE_FOLDER _ <<< "$device_spec"
        DIR="$SCREENSHOTS_DIR/$LANG/$DEVICE_FOLDER"
        if [[ -d "$DIR" ]]; then
            COUNT=$(find "$DIR" -maxdepth 1 -name "*.png" | wc -l | tr -d ' ')
            echo "  $LANG/$DEVICE_FOLDER: $COUNT screenshots"
        fi
    done
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Runs with failures:"
    for failure in "${FAILED[@]}"; do
        echo "  - $failure"
    done
    exit 1
fi

echo ""
echo "Output directory: $SCREENSHOTS_DIR/"
