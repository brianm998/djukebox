#!/bin/bash
# s1294: the AsyncAudioPlayer tests keep their TrackFetcher alive.
skip() { echo "s1294: skipped: $*"; exit 0; }
[ -n "${MASON_SKIP_SWIFT:-}" ] && skip "MASON_SKIP_SWIFT is set"
[ "$(uname)" = Darwin ] || skip "not Darwin"
command -v swift >/dev/null 2>&1 || skip "swift is missing"

set -euo pipefail
cd "$(dirname "$0")/../.."

swift test --package-path DJukeboxClient --filter AsyncAudioPlayerTests

echo "s1294: ok"
