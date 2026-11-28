#!/bin/bash
# s1277: release_github.sh and release.yml agree on release/<version> tags.
set -euo pipefail
cd "$(dirname "$0")/../.."

fail() { echo "s1277: $*" >&2; exit 1; }

version=$(scripts/version.sh)
workflow=.github/workflows/release.yml

grep -qF "tags: ['release/*']" "$workflow" || fail "$workflow: no release/* trigger"
grep -qF "'v*'" "$workflow" && fail "$workflow: still triggers on v*"
grep -qF "if: startsWith(github.ref, 'refs/tags/release/')" "$workflow" || fail "$workflow: publish gate"
grep -qF '"${GITHUB_REF_NAME#release/}" != "$V"' "$workflow" || fail "$workflow: tag check"
grep -qF 'echo "tag=release/$V"' "$workflow" || fail "$workflow: tag output"

[[ -x release_github.sh ]] || fail "release_github.sh is not executable"
# an argument is refused before any git command runs
out=$(./release_github.sh 9.9.9) && fail "release_github.sh accepted an argument"
[[ "$out" == *"takes no arguments"* ]] || fail "unexpected refusal: $out"

echo "s1277: ok ($version)"
