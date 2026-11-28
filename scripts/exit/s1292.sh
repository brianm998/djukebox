#!/bin/bash
# s1292: the AsyncAudioPlayer tests keep their TrackFetcher alive.
set -euo pipefail
cd "$(dirname "$0")/../.."

skip() { echo "s1292: skipped: $*" >&2; exit 0; }

[ -n "${MASON_SKIP_SWIFT:-}" ] && skip "MASON_SKIP_SWIFT is set"
[ "$(uname)" = Darwin ] || skip "not Darwin"
command -v swift >/dev/null 2>&1 || skip "swift is missing"

swift test --package-path DJukeboxClient --filter AsyncAudioPlayerTests

echo "s1292: ok"
