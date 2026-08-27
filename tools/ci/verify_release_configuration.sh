#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project_file="$repo_root/Cauldron.xcodeproj/project.pbxproj"
app_info="$repo_root/Cauldron/Info.plist"
app_entitlements="$repo_root/Cauldron/Cauldron.entitlements"
catalyst_entitlements="$repo_root/Cauldron/CauldronCatalyst.entitlements"
widget_entitlements="$repo_root/CauldronWidget/CauldronWidget.entitlements"

fail() {
    printf 'Release configuration error: %s\n' "$1" >&2
    exit 1
}

assert_assignment_count() {
    local assignment="$1"
    local expected_count="$2"
    local actual_count
    actual_count="$(grep -F -c "$assignment" "$project_file" || true)"
    [[ "$actual_count" == "$expected_count" ]] ||
        fail "Expected $expected_count project assignments for '$assignment'; found $actual_count."
}

assert_plist_raw() {
    local plist="$1"
    local key_path="$2"
    local expected="$3"
    local actual
    actual="$(plutil -extract "$key_path" raw -o - "$plist")"
    [[ "$actual" == "$expected" ]] ||
        fail "Expected $key_path in ${plist#"$repo_root/"} to be '$expected'; found '$actual'."
}

assert_plist_json() {
    local plist="$1"
    local key_path="$2"
    local expected="$3"
    local actual
    actual="$(plutil -extract "$key_path" json -o - "$plist")"
    [[ "$actual" == "$expected" ]] ||
        fail "Expected $key_path in ${plist#"$repo_root/"} to be '$expected'; found '$actual'."
}

assert_type_declaration() {
    local plist="$1"
    local declarations_key="$2"
    local identifier="$3"
    local conforms_to="$4"
    local filename_extension="${5:-}"
    local index=0
    local actual_identifier

    while actual_identifier="$(
        plutil -extract "$declarations_key.$index.UTTypeIdentifier" raw -o - "$plist" 2>/dev/null
    )"; do
        if [[ "$actual_identifier" == "$identifier" ]]; then
            assert_plist_raw "$plist" "$declarations_key.$index.UTTypeConformsTo.0" "$conforms_to"
            if [[ -n "$filename_extension" ]]; then
                assert_plist_raw \
                    "$plist" \
                    "$declarations_key.$index.UTTypeTagSpecification.public\.filename-extension.0" \
                    "$filename_extension"
            fi
            return
        fi
        index=$((index + 1))
    done

    fail "Expected $declarations_key in ${plist#"$repo_root/"} to include '$identifier'."
}

assert_plist_array_contains() {
    local plist="$1"
    local key_path="$2"
    local expected="$3"
    local json
    json="$(plutil -extract "$key_path" json -o - "$plist")"
    [[ "$json" == *"\"$expected\""* ]] ||
        fail "Expected $key_path in ${plist#"$repo_root/"} to contain '$expected'."
}

assert_assignment_count \
    'CODE_SIGN_ENTITLEMENTS = CauldronWidget/CauldronWidget.entitlements;' \
    2
assert_assignment_count \
    '"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = Cauldron/CauldronCatalyst.entitlements;' \
    2

assert_type_declaration \
    "$app_info" \
    'UTExportedTypeDeclarations' \
    'Nadav.Cauldron.library-archive' \
    'public.json' \
    'cauldron'
assert_type_declaration \
    "$app_info" \
    'UTImportedTypeDeclarations' \
    'app.cauldron.library-archive' \
    'public.json'

assert_plist_json \
    "$widget_entitlements" \
    'com\.apple\.security\.application-groups' \
    '["group.Nadav.Cauldron"]'
assert_plist_json \
    "$widget_entitlements" \
    'com\.apple\.developer\.icloud-container-identifiers' \
    '["iCloud.Nadav.Cauldron"]'

for entitlements in "$app_entitlements" "$catalyst_entitlements"; do
    assert_plist_array_contains \
        "$entitlements" \
        'com\.apple\.developer\.associated-domains' \
        'applinks:cauldron-f900a.web.app'
    assert_plist_array_contains \
        "$entitlements" \
        'com\.apple\.developer\.associated-domains' \
        'applinks:cauldron-f900a.firebaseapp.com'
done

assert_plist_raw "$catalyst_entitlements" 'com\.apple\.security\.app-sandbox' 'true'
assert_plist_raw "$catalyst_entitlements" 'com\.apple\.security\.network\.client' 'true'
assert_plist_json \
    "$catalyst_entitlements" \
    'com\.apple\.developer\.icloud-container-identifiers' \
    '["iCloud.Nadav.Cauldron"]'

printf 'Release configuration verified.\n'
