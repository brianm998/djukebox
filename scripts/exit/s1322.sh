#!/bin/bash
# s1322: landing batches run the Swift suites over the merged tree.
set -euo pipefail
cd "$(dirname "$0")/../.."

fail() { echo "s1322: $*" >&2; exit 1; }
has() { grep -qxF -- "$2" "$1" || fail "$1 lacks: $2"; }

has .mason/landing.toml '[[tier]]'
has .mason/landing.toml 'name   = "batch"'
has .mason/landing.toml 'suites = ["swift-common", "swift-server", "swift-client"]'

has .mason/mason.toml '[impact]'
has .mason/mason.toml '"DJukeboxCommon/**" = ["swift-common", "swift-server", "swift-client"]'
has .mason/mason.toml '"DJukeboxClient/**" = ["swift-client"]'
has .mason/mason.toml '"djukebox_server/**" = ["swift-server"]'
has .mason/mason.toml '"docs/**" = []'
has .mason/mason.toml '"**/*.md" = []'
has .mason/mason.toml '"scripts/exit/**" = []'

if command -v mason >/dev/null 2>&1; then
  mason definition check .mason/mason.toml
else
  echo "s1322: mason is missing, definition not validated"
fi

echo "s1322: ok"
