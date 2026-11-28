#!/bin/bash
# Exit check for s1265: offline plays and skips are kept and uploaded later.
set -euo pipefail
cd "$(dirname "$0")/../.."
swift test --package-path DJukeboxClient
