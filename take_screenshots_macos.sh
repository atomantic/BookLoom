#!/bin/bash
#
# take_screenshots_macos.sh - Capture macOS App Store screenshots.
#
# Prerequisites:
#   The invoking terminal needs Screen Recording permission. Accessibility
#   permission is recommended so the script can raise and resize the app window.
#
# Usage:
#   ./take_screenshots_macos.sh
#   ./take_screenshots_macos.sh en
#

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/BookLoom.xcodeproj"
SCHEME="BookLoom_macOS"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"
DERIVED_DATA="$PROJECT_DIR/.build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/BookLoom.app"

ALL_LANGUAGES=("en")
WINDOW_X=100
WINDOW_Y=100
WINDOW_WIDTH=1440
WINDOW_HEIGHT=900

LANGUAGES=()
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: $0 [locale ...]"
            echo "Requires Screen Recording permission for your terminal."
            exit 0
            ;;
        *) LANGUAGES+=("$arg") ;;
    esac
done
[[ ${#LANGUAGES[@]} -eq 0 ]] && LANGUAGES=("${ALL_LANGUAGES[@]}")

echo "=========================================="
echo "  BookLoom macOS Screenshot Capture"
echo "=========================================="
echo "  Languages: ${LANGUAGES[*]}"
echo "  Window:    ${WINDOW_WIDTH}x${WINDOW_HEIGHT}"
echo "  Output:    $SCREENSHOTS_DIR/{locale}/macos/"
echo "=========================================="
echo ""

echo "Building macOS app..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet
echo "Build complete"
echo ""

if [[ ! -d "$APP_PATH" ]]; then
    echo "App not found at $APP_PATH"
    exit 1
fi

run_osascript_with_timeout() {
    local script="$1"
    local attempts="${2:-50}"

    osascript -e "$script" >/dev/null 2>&1 &
    local script_pid=$!
    for ((i = 0; i < attempts; i++)); do
        if ! kill -0 "$script_pid" 2>/dev/null; then
            wait "$script_pid" 2>/dev/null || true
            return 0
        fi
        sleep 0.1
    done
    kill "$script_pid" 2>/dev/null || true
    wait "$script_pid" 2>/dev/null || true
}

setup_window() {
    run_osascript_with_timeout "
    tell application \"BookLoom\" to activate
    delay 0.5
    tell application \"System Events\"
        tell process \"BookLoom\"
            set frontmost to true
            if (count of windows) = 0 then
                click menu item \"New Window\" of menu \"File\" of menu bar 1
                delay 0.5
            end if
            if (count of windows) > 0 then
                set position of first window to {$WINDOW_X, $WINDOW_Y}
                set size of first window to {$WINDOW_WIDTH, $WINDOW_HEIGHT}
                perform action \"AXRaise\" of first window
            end if
        end tell
    end tell"
}

bookloom_window_id() {
    swift - <<'SWIFT'
import Foundation
import CoreGraphics

func number(_ value: Any?) -> Double {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    return 0
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let candidates = windows.compactMap { window -> (area: Double, id: UInt32)? in
    guard (window[kCGWindowOwnerName as String] as? String) == "BookLoom",
          number(window[kCGWindowLayer as String]) == 0,
          let id = window[kCGWindowNumber as String] as? UInt32,
          let bounds = window[kCGWindowBounds as String] as? [String: Any] else {
        return nil
    }

    let width = number(bounds["Width"])
    let height = number(bounds["Height"])
    guard width > 600, height > 500 else { return nil }
    return (width * height, id)
}

if let window = candidates.max(by: { $0.area < $1.area }) {
    print(window.id)
}
SWIFT
}

capture_window() {
    local output_path="$1"
    setup_window
    sleep 0.6

    local window_id
    window_id="$(bookloom_window_id | tr -d '[:space:]')"
    if [[ -n "$window_id" ]]; then
        screencapture -l "$window_id" -o -x "$output_path"
    else
        screencapture -R "${WINDOW_X},${WINDOW_Y},${WINDOW_WIDTH},${WINDOW_HEIGHT}" -o -x "$output_path"
    fi
}

capture_page() {
    local route="$1"
    local output="$2"
    killall BookLoom 2>/dev/null || true
    sleep 0.5
    open "$APP_PATH" --args \
        -SeedSampleData \
        -screenshotRoute "$route" \
        -AppleLanguages "($CURRENT_LANG)" \
        -AppleLocale "$CURRENT_LANG"
    sleep 3
    capture_window "$output"
}

capture_locale() {
    local lang="$1"
    local out_dir="$SCREENSHOTS_DIR/$lang/macos"
    mkdir -p "$out_dir"
    rm -f "$out_dir"/*.png

    echo "Capturing $lang..."
    CURRENT_LANG="$lang"

    capture_page library     "$out_dir/01_library.png"
    capture_page clubs       "$out_dir/02_clubs.png"
    capture_page clubHome    "$out_dir/03_club_home.png"
    capture_page currentRead "$out_dir/04_current_read.png"
    capture_page poll        "$out_dir/05_vote.png"
    capture_page meeting     "$out_dir/06_meeting.png"

    killall BookLoom 2>/dev/null || true
    sleep 1

    for file in "$out_dir"/*.png; do
        [[ -f "$file" ]] || continue
        sips --resampleHeightWidth 1800 2880 "$file" --out "$file" >/dev/null 2>&1
    done

    local count
    count=$(find "$out_dir" -maxdepth 1 -name "*.png" | wc -l | tr -d ' ')
    echo "  Complete: $lang/macos ($count screenshots)"
}

FAILED=()
for lang in "${LANGUAGES[@]}"; do
    if ! capture_locale "$lang"; then
        FAILED+=("$lang")
    fi
done

echo ""
echo "=========================================="
echo "  macOS Screenshot Capture Complete"
echo "=========================================="
for lang in "${LANGUAGES[@]}"; do
    dir="$SCREENSHOTS_DIR/$lang/macos"
    if [[ -d "$dir" ]]; then
        count=$(find "$dir" -maxdepth 1 -name "*.png" | wc -l | tr -d ' ')
        echo "  $lang/macos: $count screenshots"
    fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Failed: ${FAILED[*]}"
    exit 1
fi

echo ""
echo "Output directory: $SCREENSHOTS_DIR/"
