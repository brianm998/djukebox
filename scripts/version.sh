#!/bin/bash
# Prints the DJukebox version: the value of DJukeboxVersion.current in
# DJukeboxCommon. Fails loudly rather than printing anything doubtful.
set -euo pipefail

file="$(cd "$(dirname "$0")" && pwd)/../DJukeboxCommon/Sources/DJukeboxCommon/Version.swift"

fail() {
    echo "version.sh: $*" >&2
    exit 1
}

[[ -r "$file" ]] || fail "cannot read $file"

version=$(sed -n 's/^[[:space:]]*public static let current = "\([^"]*\)"[[:space:]]*$/\1/p' "$file")

[[ -n "$version" ]] || fail "no 'public static let current = \"...\"' line in $file"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "expected exactly one X.Y.Z version in $file, got: $version"

echo "$version"
