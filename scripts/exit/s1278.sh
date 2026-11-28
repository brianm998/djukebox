#!/bin/bash
# s1278: release_darwin.sh, the server payload and release.yml fit together.
# Static checks and a dry run of a tarball install; nothing is built or signed.
set -euo pipefail
cd "$(dirname "$0")/../.."

fail() { echo "s1278: $*" >&2; exit 1; }
has() { grep -qF -- "$2" "$1" || fail "$1: missing: $2"; }

server=djukebox_server
payload=$server/scripts/server_payload.sh
installer=$server/scripts/install_launch_agent.sh
workflow=.github/workflows/release.yml

for f in release_darwin.sh "$installer" "$server/scripts/uninstall_launch_agent.sh" "$payload"; do
    /bin/bash -n "$f" || fail "$f: syntax"
done
[[ -x release_darwin.sh ]] || fail "release_darwin.sh is not executable"
grep -v '^[[:space:]]*#' release_darwin.sh | grep -qE '(^|[[:space:];&|(])git[[:space:]]' \
    && fail "release_darwin.sh runs git"
has release_darwin.sh 'scripts/version.sh'
has release_darwin.sh 'server_payload.sh'
has "$installer" '. "$SCRIPT_DIR/server_payload.sh"'
grep -qE 'for [a-z]+ in .*\*\.bundle' "$installer" release_darwin.sh \
    && fail "the payload file list is duplicated"

has "$workflow" "tags: ['release/*']"
has "$workflow" "if: startsWith(github.ref, 'refs/tags/release/') && github.event_name == 'push'"
[[ $(grep -c 'needs: \[version, check\]' "$workflow") -eq 3 ]] || fail "$workflow: signing jobs must need check"
for t in --server --mac --ios; do has "$workflow" "run: ./release_darwin.sh $t"; done
has "$workflow" 'draft:                   true'
# the iOS job gets no Developer ID certificate
sed -n '/^  ios-app:/,/^  release-publish:/p' "$workflow" | grep -q 'APPLE_CERTIFICATE' \
    && fail "$workflow: the iOS job reads the certificate"
grep -q 'APPLE_SIGN_IDENTITY' "$workflow" release_darwin.sh && fail "APPLE_SIGN_IDENTITY is still used"

pbxproj=mac_client/DJukeboxMac/DJukeboxMac.xcodeproj/project.pbxproj
grep -q 'ked-to-it' "$pbxproj" && fail "$pbxproj: old bundle id"
[[ $(grep -c 'PRODUCT_BUNDLE_IDENTIFIER = com.brianm998.djukebox.mac;' "$pbxproj") -eq 2 ]] \
    || fail "$pbxproj: bundle id"

[[ -d releases ]] || fail "no releases/ directory"
plutil -lint "$server/launchd/com.brianm998.djukebox.plist.template" >/dev/null || fail "plist template"

# an extracted tarball installs without building (stub binary, dry run only)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root="$tmp/payload"
products="$tmp/products"
mkdir -p "$root/scripts" "$root/launchd" "$products/stub.bundle" "$tmp/out"
printf '#!/bin/sh\n' > "$products/Run"
chmod +x "$products/Run"
touch "$products/libswiftCompatibilitySpan.dylib"
(
    . "$payload"
    server_payload_stage "$products" "$root/bin" prebuilt
    cp "$server/$SERVER_PAYLOAD_TEMPLATE" "$root/$SERVER_PAYLOAD_TEMPLATE"
    for f in $SERVER_PAYLOAD_SCRIPTS; do cp "$server/$f" "$root/$f"; done
)
for f in bin/Run bin/stub.bundle bin/libswiftCompatibilitySpan.dylib; do
    [[ -e "$root/$f" ]] || fail "payload lacks $f"
done
out=$("$root/scripts/install_launch_agent.sh" --new-db --dry-run "$tmp/out") || fail "tarball dry run failed"
[[ "$out" == *"(no build)"* ]] || fail "tarball install would build: $out"
[[ "$out" == *"keep the signatures"* ]] || fail "tarball install would re-sign: $out"
[[ "$out" == *"Application Support/DJukebox/db.sqlite"* ]] || fail "tarball database default: $out"
out=$("$root/scripts/install_launch_agent.sh" --new-db --sign-identity X --dry-run "$tmp/out")
[[ "$out" == *"(identity: X)"* ]] || fail "--sign-identity ignored: $out"
out=$("$installer" --new-db --dry-run "$tmp/out")
[[ "$out" == *"swift build"* && "$out" == *"(identity: -)"* ]] || fail "source install changed: $out"

echo "s1278: ok"
