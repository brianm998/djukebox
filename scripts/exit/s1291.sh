#!/bin/bash
# s1291: AsyncAudioPlayer tests keep their TrackFetcher alive.
if [ -n "${MASON_SKIP_SWIFT:-}" ] || [ "$(uname)" != Darwin ] || ! command -v swift >/dev/null 2>&1; then
    echo "s1291: skipped (MASON_SKIP_SWIFT set, not Darwin, or no swift)"
    exit 0
fi
set -euo pipefail
cd "$(dirname "$0")/../.."

swift test --package-path DJukeboxClient --filter AsyncAudioPlayerTests

echo "s1291: ok"
