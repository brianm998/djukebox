#!/bin/bash
# s1269: scripts/version.sh agrees with both Xcode projects and Info.plists, and
# fails when the Swift constant is missing or malformed.
set -euo pipefail
cd "$(dirname "$0")/../.."

fail() { echo "s1269: $*" >&2; exit 1; }

version=$(scripts/version.sh)

for project in ios_client/DJukeboxiOS/DJukeboxiOS mac_client/DJukeboxMac/DJukeboxMac; do
    pbxproj="$project.xcodeproj/project.pbxproj"
    # the app target's Debug and Release configurations
    [[ $(grep -c "MARKETING_VERSION = $version;" "$pbxproj") -eq 2 ]] || fail "$pbxproj: MARKETING_VERSION"
    [[ $(grep -c "CURRENT_PROJECT_VERSION = " "$pbxproj") -eq 2 ]] || fail "$pbxproj: CURRENT_PROJECT_VERSION"
    grep -qF '<string>$(MARKETING_VERSION)</string>' "$project/Info.plist" || fail "$project/Info.plist: short version"
    grep -qF '<string>$(CURRENT_PROJECT_VERSION)</string>' "$project/Info.plist" || fail "$project/Info.plist: build number"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dir="$tmp/DJukeboxCommon/Sources/DJukeboxCommon"
mkdir -p "$tmp/scripts" "$dir"
cp scripts/version.sh "$tmp/scripts/"
"$tmp/scripts/version.sh" >/dev/null 2>&1 && fail "accepted a missing Version.swift"
for bad in '' 'public static let current = "one"'; do
    echo "$bad" > "$dir/Version.swift"
    "$tmp/scripts/version.sh" >/dev/null 2>&1 && fail "accepted: '$bad'"
done

echo "s1269: ok ($version)"
