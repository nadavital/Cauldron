#!/bin/bash
set -euo pipefail

version_output="$(xcodebuild -version)"
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
build_version="$(sed -n 's/^Build version //p' <<< "$version_output")"

printf '%s\n' "$version_output"
printf 'iPhoneOS SDK %s\n' "$sdk_version"
printf 'DEVELOPER_DIR=%s\n' "${DEVELOPER_DIR:-<image default>}"
printf 'ImageOS=%s ImageVersion=%s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}"

if [[ "$version_output" != Xcode\ 27.* ]]; then
    printf '::error title=Unexpected Xcode toolchain::Expected Xcode 27.x from the xcode-27 runner, got %s\n' "$version_output" >&2
    exit 1
fi

if [[ "$sdk_version" != 27.* ]]; then
    printf '::error title=Unexpected iOS SDK::Expected iPhoneOS 27.x, got %s\n' "$sdk_version" >&2
    exit 1
fi

if [[ -n "${EXPECTED_XCODE_BUILD:-}" && "$build_version" != "$EXPECTED_XCODE_BUILD" ]]; then
    if [[ "${REQUIRE_EXACT_XCODE_BUILD:-0}" == "1" ]]; then
        printf '::error title=Unexpected Xcode build::Expected release toolchain %s, got %s.\n' "$EXPECTED_XCODE_BUILD" "$build_version" >&2
        exit 1
    fi
    printf '::warning title=Xcode preview image rotated::Expected %s, got %s. Major-version validation passed.\n' "$EXPECTED_XCODE_BUILD" "$build_version" >&2
fi
