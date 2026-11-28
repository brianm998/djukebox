#!/bin/bash
# s1279: local queue move/stop tests pass (stale and out-of-range indexes).
set -euo pipefail
cd "$(dirname "$0")/../../DJukeboxClient"

swift test --filter 'AVDoghouseAudioPlayerQueueTests|AsyncAudioPlayerTests'

echo "s1279: ok"
