#!/bin/zsh

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <simulator-udid> <built-app-path> [output-directory]" >&2
    exit 64
fi

device_id="$1"
app_path="$2"
output_directory="${3:-appstorescreenshots/appscreenshots/iPhone/2.0}"
developer_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
simctl="$developer_directory/usr/bin/simctl"
bundle_id="Nadav.Cauldron.dev"

mkdir -p "$output_directory"

"$simctl" bootstatus "$device_id" -b
"$simctl" install "$device_id" "$app_path"
"$simctl" status_bar "$device_id" override \
    --time 9:41 \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4

capture_tab() {
    local tab="$1"
    local filename="$2"
    "$simctl" launch --terminate-running-process "$device_id" "$bundle_id" \
        --cauldron-simulator-qa \
        "--cauldron-screenshot-tab=$tab"
    sleep 4
    "$simctl" io "$device_id" screenshot "$output_directory/$filename.PNG"
}

capture_scene() {
    local scene="$1"
    local filename="$2"
    "$simctl" launch --terminate-running-process "$device_id" "$bundle_id" \
        --cauldron-simulator-qa \
        "--cauldron-screenshot-scene=$scene"
    sleep 4
    "$simctl" io "$device_id" screenshot "$output_directory/$filename.PNG"
}

capture_tab cook cook_tab
capture_scene recipe_view recipe_view
capture_tab friends friends_tab
capture_tab search search_tab
capture_scene generate_recipe generate_recipe
capture_scene collection_view collection_view
capture_scene cook_mode cook_mode

# A real Live Activity requires the simulator to be locked after this route
# starts ActivityKit. Set CAPTURE_LIVE_ACTIVITY=1, lock the Simulator with
# Command-L while the script pauses, then press Return in this terminal.
if [[ "${CAPTURE_LIVE_ACTIVITY:-0}" == "1" ]]; then
    "$simctl" launch --terminate-running-process "$device_id" "$bundle_id" \
        --cauldron-simulator-qa \
        --cauldron-screenshot-scene=live_activity
    sleep 4
    echo "Lock the Simulator with Command-L, then press Return to capture the real Live Activity."
    read -r
    "$simctl" io "$device_id" screenshot "$output_directory/live_activity.PNG"
fi

echo "Captured current App Store source screenshots in $output_directory"
