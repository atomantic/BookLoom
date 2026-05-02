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
PROJECT="$PROJECT_DIR/PlotLoom.xcodeproj"
SCHEME="PlotLoom_macOS"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"
DERIVED_DATA="$PROJECT_DIR/.build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/PlotLoom.app"

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
echo "  PlotLoom macOS Screenshot Capture"
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

setup_window() {
    osascript -e "
    tell application \"PlotLoom\" to activate
    delay 0.5
    tell application \"System Events\"
        tell process \"PlotLoom\"
            set frontmost to true
            if (count of windows) > 0 then
                set position of first window to {$WINDOW_X, $WINDOW_Y}
                set size of first window to {$WINDOW_WIDTH, $WINDOW_HEIGHT}
                perform action \"AXRaise\" of first window
            end if
        end tell
    end tell" 2>/dev/null || true
}

capture_window() {
    local output_path="$1"
    setup_window
    sleep 0.6
    screencapture -R "${WINDOW_X},${WINDOW_Y},${WINDOW_WIDTH},${WINDOW_HEIGHT}" -o -x "$output_path"
}

capture_page() {
    local route="$1"
    local output="$2"
    osascript -e "tell application \"PlotLoom\" to open location \"plotloom://screenshot/$route\"" 2>/dev/null || true
    sleep 1.5
    capture_window "$output"
}

capture_locale() {
    local lang="$1"
    local out_dir="$SCREENSHOTS_DIR/$lang/macos"
    mkdir -p "$out_dir"
    rm -f "$out_dir"/*.png

    echo "Capturing $lang..."
    killall PlotLoom 2>/dev/null || true
    sleep 1

    open "$APP_PATH" --args \
        -SeedSampleData \
        -AppleLanguages "($lang)" \
        -AppleLocale "$lang"

    sleep 3
    setup_window

    capture_page clubs       "$out_dir/01_clubs.png"
    capture_page clubHome    "$out_dir/02_club_home.png"
    capture_page currentRead "$out_dir/03_current_read.png"
    capture_page poll        "$out_dir/04_vote.png"
    capture_page meeting     "$out_dir/05_meeting.png"

    killall PlotLoom 2>/dev/null || true
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
