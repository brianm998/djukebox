#!/bin/bash
# s1290: the AsyncAudioPlayer tests pass.
skip() { echo "s1290: skipped: $*"; exit 0; }
[[ -n "${MASON_SKIP_SWIFT:-}" ]] && skip "MASON_SKIP_SWIFT is set"
[[ $(uname) == Darwin ]] || skip "not macOS"
command -v swift >/dev/null 2>&1 || skip "swift is missing"

set -euo pipefail
cd "$(dirname "$0")/../../DJukeboxClient"

swift test --filter AsyncAudioPlayerTests

echo "s1290: ok"
