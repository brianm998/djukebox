#!/bin/bash
#
# Dead-code scan of the whole project with Periphery (https://github.com/peripheryapp/periphery).
#
# Builds DJukeboxCommon, DJukeboxClient, djukebox_server and both app schemes
# (DJukeboxiOS, DJukebox), then runs ONE Periphery scan over all of their index
# stores. Scanning them together matters: a public declaration in a package
# counts as used if any app or the server uses it, and code behind
# `#if os(iOS)` / `#if os(macOS)` is judged by the build that compiles it.
#
# usage: scripts/periphery-scan.sh [extra `periphery scan` options]
#   e.g. scripts/periphery-scan.sh --strict          # fail on any finding
#
# Settings and the known false positives are in .periphery.yml at the repo root.
# Build products go in .build/periphery (git-ignored). Index data is thrown away
# before each run, so stale entries cannot hide or invent findings. The first run
# takes 20 minutes or more.

set -euo pipefail

if ! command -v periphery >/dev/null 2>&1; then
    echo "periphery is not installed: brew install periphery" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"

WORK="$ROOT/.build/periphery"
LOGS="$WORK/logs"
# Our own modules are recompiled on every run; dependency checkouts and their
# compiled output are kept, because rebuilding them takes many minutes.
rm -rf "$WORK/xcode" "$LOGS"
# Forgetting SwiftPM's build plan makes it notice added and removed files.
rm -f "$WORK"/*/build.db "$WORK"/*/debug.yaml
for debug in "$WORK"/*/*-apple-macosx/debug; do
    [ -d "$debug" ] || continue
    rm -rf "$debug/index"
    for module in App Run AppTests DJukeboxClient DJukeboxClientTests DJukeboxCommon \
                  DJukeboxCommonTests; do
        rm -rf "$debug/$module.build"
    done
done
mkdir -p "$LOGS"

INDEX_STORES=()

# Runs a build quietly; shows the end of its log if it fails.
run_build() {
    local name="$1"
    shift
    echo "building $name..." >&2
    if ! "$@" >"$LOGS/$name.log" 2>&1; then
        tail -40 "$LOGS/$name.log" >&2
        echo "$name failed to build; full log: $LOGS/$name.log" >&2
        exit 1
    fi
}

build_package() {
    local dir="$1"
    local flags=(--package-path "$dir" --scratch-path "$WORK/$dir"
                 --only-use-versions-from-resolved-file --skip-update
                 --build-tests --enable-index-store)
    # DJukeboxClient has no external dependencies, hence no Package.resolved.
    if [ ! -f "$dir/Package.resolved" ]; then
        flags=(--package-path "$dir" --scratch-path "$WORK/$dir"
               --build-tests --enable-index-store)
    fi
    run_build "$dir" swift build "${flags[@]}"
    INDEX_STORES+=("$(swift build "${flags[@]}" --show-bin-path)/index/store")
}

# Both apps are products called "DJukebox", so their modules would share a name
# and Periphery would confuse the two. PRODUCT_MODULE_NAME is overridden to the
# target name, which tells them apart (package modules already match theirs).
# SYMROOT and OBJROOT keep the build inside our scratch directory even when Xcode
# is set to a custom build location; an up-to-date build there would not index.
build_scheme() {
    local project="$1" scheme="$2" destination="$3"
    local derived="$WORK/xcode/$scheme"
    run_build "$scheme" xcodebuild build \
        -project "$project" \
        -scheme "$scheme" \
        -destination "$destination" \
        -derivedDataPath "$derived" \
        SYMROOT="$derived/Build/Products" \
        OBJROOT="$derived/Build/Intermediates" \
        COMPILER_INDEX_STORE_ENABLE=YES \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        'PRODUCT_MODULE_NAME=$(TARGET_NAME:c99extidentifier)'
    INDEX_STORES+=("$derived/Index.noindex/DataStore")
}

build_package DJukeboxCommon
build_package DJukeboxClient
build_package djukebox_server
build_scheme ios_client/DJukeboxiOS/DJukeboxiOS.xcodeproj DJukeboxiOS \
    'generic/platform=iOS Simulator'
build_scheme mac_client/DJukeboxMac/DJukeboxMac.xcodeproj DJukebox \
    'platform=macOS'

# Join arguments as a JSON array of strings.
json_array() {
    local out="" item
    for item in "$@"; do
        item="${item//\\/\\\\}"
        item="${item//\"/\\\"}"
        out="$out${out:+, }\"$item\""
    done
    printf '[%s]' "$out"
}

# Interface Builder files and Info.plists name classes and actions that no Swift
# code refers to, so Periphery needs to read them.
PLISTS=()
XIBS=()
while IFS= read -r file; do
    case "$file" in
        *.plist) PLISTS+=("$ROOT/$file") ;;
        *)       XIBS+=("$ROOT/$file") ;;
    esac
done < <(git ls-files 'ios_client/*Info.plist' 'mac_client/*Info.plist' \
                      '*.storyboard' '*.xib')

CONFIG="$WORK/project.json"
cat >"$CONFIG" <<EOF
{
  "indexstores": $(json_array "${INDEX_STORES[@]}"),
  "test_targets": ["DJukeboxCommonTests", "DJukeboxClientTests", "AppTests"],
  "plists": $(json_array "${PLISTS[@]}"),
  "xibs": $(json_array "${XIBS[@]}"),
  "xcdatamodels": [],
  "xcmappingmodels": []
}
EOF

echo "scanning..." >&2
periphery scan \
    --config "$ROOT/.periphery.yml" \
    --generic-project-config "$CONFIG" \
    --relative-results \
    --disable-update-check \
    "$@"
