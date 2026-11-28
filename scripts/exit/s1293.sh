#!/bin/bash
# s1293: the AsyncAudioPlayer tests pass (their fixture keeps the TrackFetcher alive).
skip() { echo "s1293: skipped: $*"; exit 0; }
[ -n "${MASON_SKIP_SWIFT:-}" ] && skip "MASON_SKIP_SWIFT is set"
[ "$(uname)" = Darwin ] || skip "not Darwin"
command -v swift >/dev/null 2>&1 || skip "swift is missing"

set -euo pipefail
cd "$(dirname "$0")/../../DJukeboxClient"

swift test --filter 'AsyncAudioPlayerTests'

echo "s1293: ok"
