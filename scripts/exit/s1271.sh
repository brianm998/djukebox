#!/bin/bash
# s1271: the dead-code scan script and its config are in place, and TODO holds no
# old work items. The scan itself is slow and needs periphery; run it by hand.
set -euo pipefail
cd "$(dirname "$0")/../.."

fail() { echo "s1271: $*" >&2; exit 1; }

[[ -x scripts/periphery-scan.sh ]] || fail "scripts/periphery-scan.sh is not executable"
bash -n scripts/periphery-scan.sh || fail "scripts/periphery-scan.sh does not parse"
[[ -f .periphery.yml ]] || fail ".periphery.yml is missing"
grep -qF 'docs/stages/s1271.md' TODO || fail "TODO does not point at the ticket list"
grep -qiE 'volume control|cache files locally|^bugs:|^new features:' TODO && fail "TODO lists old items"

echo "s1271: ok"
