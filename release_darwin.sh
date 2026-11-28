#!/bin/bash
# Builds, signs and notarizes the DJukebox release artifacts on a Mac. The
# release workflow runs this same script, one target per job.
#
# usage: ./release_darwin.sh [--server] [--mac] [--ios] [--dist DIR] [--unsigned]
#   With no target all three are built. Output goes to DIR (default dist/):
#     --server  djukebox-server-macos-<version>.tar.gz
#     --mac     DJukebox-<version>.dmg
#     --ios     DJukeboxiOS-<version>.xcarchive, uploaded to TestFlight
#   --unsigned    server only: ad hoc signature, no notarization (not releasable)
#
# Environment:
#   APPLE_API_KEY_ID, APPLE_API_ISSUER_ID and either APPLE_API_KEY_PATH (a .p8
#       file) or APPLE_API_KEY_P8_BASE64: the App Store Connect API key, used to
#       notarize and, for iOS, to sign and upload. Without it --ios is skipped.
#   APPLE_TEAM_ID  default: DEVELOPMENT_TEAM in the Xcode project
#   APPLE_CERTIFICATE_P12_BASE64, APPLE_CERTIFICATE_PASSWORD, KEYCHAIN_PASSWORD
#       optional: a Developer ID Application certificate to import into a
#       temporary keychain. Without it the login keychains are searched.
#   BUILD_NUMBER   CFBundleVersion (default: the Actions run number.attempt, or 1)
#
# The version comes from scripts/version.sh. bash 3.2 compatible.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }
step() { echo ""; echo "==> $*"; }
usage() { echo "usage: $0 [--server] [--mac] [--ios] [--dist DIR] [--unsigned]"; }

DO_SERVER=0
DO_MAC=0
DO_IOS=0
UNSIGNED=0
DIST="$ROOT/dist"
while [ $# -gt 0 ]; do
  case "$1" in
    --server) DO_SERVER=1; shift;;
    --mac) DO_MAC=1; shift;;
    --ios) DO_IOS=1; shift;;
    --unsigned) UNSIGNED=1; shift;;
    --dist) [ $# -ge 2 ] || die "--dist needs a directory"; DIST="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) usage >&2; die "unknown option: $1";;
  esac
done
if [ $((DO_SERVER + DO_MAC + DO_IOS)) -eq 0 ]; then
  DO_SERVER=1; DO_MAC=1; DO_IOS=1
fi

VERSION="$("$ROOT/scripts/version.sh")" || die "cannot read the version"
if [ -n "${BUILD_NUMBER:-}" ]; then
  BUILD="$BUILD_NUMBER"
elif [ -n "${GITHUB_RUN_NUMBER:-}" ]; then
  BUILD="$GITHUB_RUN_NUMBER.${GITHUB_RUN_ATTEMPT:-1}"
else
  BUILD=1
fi

mkdir -p "$DIST"
DIST="$(cd "$DIST" && pwd)"

MAC_PROJECT="$ROOT/mac_client/DJukeboxMac/DJukeboxMac.xcodeproj"
IOS_PROJECT="$ROOT/ios_client/DJukeboxiOS/DJukeboxiOS.xcodeproj"

# ── Temporary keys and keychain, removed on exit ──────────────────────────────
WORK="$(mktemp -d "${TMPDIR:-/tmp}/djukebox-release.XXXXXX")"
KEYCHAIN=""
OLD_KEYCHAINS=()
cleanup() {
  if [ -n "$KEYCHAIN" ]; then
    if [ ${#OLD_KEYCHAINS[@]} -gt 0 ]; then
      security list-keychains -d user -s "${OLD_KEYCHAINS[@]}" || true
    fi
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ── Credentials ───────────────────────────────────────────────────────────────
team_id() { # project
  local from_project
  from_project="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = \([A-Z0-9]*\);.*/\1/p' "$1/project.pbxproj" | head -1)"
  if [ -n "${APPLE_TEAM_ID:-}" ]; then
    if [ -n "$from_project" ] && [ "$from_project" != "$APPLE_TEAM_ID" ]; then
      echo "warning: APPLE_TEAM_ID differs from DEVELOPMENT_TEAM in $1; using APPLE_TEAM_ID" >&2
    fi
    echo "$APPLE_TEAM_ID"
  else
    [ -n "$from_project" ] || die "set APPLE_TEAM_ID"
    echo "$from_project"
  fi
}

# Sets API_KEY; returns 1 when the App Store Connect key is not configured.
API_KEY=""
load_api_key() {
  [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER_ID:-}" ] || return 1
  if [ -n "${APPLE_API_KEY_PATH:-}" ]; then
    [ -f "$APPLE_API_KEY_PATH" ] || die "APPLE_API_KEY_PATH: no such file"
    API_KEY="$(cd "$(dirname "$APPLE_API_KEY_PATH")" && pwd)/$(basename "$APPLE_API_KEY_PATH")"
  elif [ -n "${APPLE_API_KEY_P8_BASE64:-}" ]; then
    API_KEY="$WORK/AuthKey_${APPLE_API_KEY_ID}.p8"
    (umask 077; echo "$APPLE_API_KEY_P8_BASE64" | base64 --decode > "$API_KEY") \
      || die "cannot decode APPLE_API_KEY_P8_BASE64"
  else
    return 1
  fi
}

import_certificate() {
  [ -n "${APPLE_CERTIFICATE_P12_BASE64:-}" ] || return 0
  local password="${KEYCHAIN_PASSWORD:-$(uuidgen)}" p12="$WORK/certificate.p12" line
  step "Importing the certificate into a temporary keychain"
  (umask 077; echo "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$p12") \
    || die "cannot decode APPLE_CERTIFICATE_P12_BASE64"
  while IFS= read -r line; do
    OLD_KEYCHAINS[${#OLD_KEYCHAINS[@]}]="$line"
  done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
  KEYCHAIN="$WORK/build.keychain-db"
  security create-keychain -p "$password" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$password" "$KEYCHAIN"
  security import "$p12" -k "$KEYCHAIN" -P "${APPLE_CERTIFICATE_PASSWORD:-}" \
    -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null
  security list-keychains -d user -s "$KEYCHAIN" ${OLD_KEYCHAINS[@]+"${OLD_KEYCHAINS[@]}"}
  rm -f "$p12"
}

# Sets TEAM, and IDENTITY to the SHA-1 of the team's Developer ID Application
# certificate; also requires the notarization key.
TEAM=""
IDENTITY=""
need_developer_id() {
  [ -n "$IDENTITY" ] && return 0
  load_api_key || die "notarizing needs APPLE_API_KEY_ID, APPLE_API_ISSUER_ID and the .p8 key"
  TEAM="$(team_id "$MAC_PROJECT")"
  import_certificate
  local found
  found="$(security find-identity -v -p codesign ${KEYCHAIN:+"$KEYCHAIN"} \
    | grep "\"Developer ID Application: .*($TEAM)\"" | head -1)" || true
  [ -n "$found" ] || die "no 'Developer ID Application: … ($TEAM)' identity in the keychain"
  IDENTITY="$(echo "$found" | awk '{print $2}')"
  echo "signing identity: $(echo "$found" | sed 's/^[^"]*"//; s/"$//')"
}

# notarize FILE  (a .zip or .dmg)
notarize() {
  local result="$WORK/notary.json" status id
  step "Notarizing $(basename "$1")"
  # notarytool can exit 0 for a rejected submission, so read the status
  xcrun notarytool submit "$1" \
    --key "$API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" \
    --wait --output-format json > "$result" || { cat "$result" >&2; die "notarytool submit failed"; }
  cat "$result"; echo ""
  status="$(plutil -extract status raw -o - "$result")" || die "no status from notarytool"
  if [ "$status" != Accepted ]; then
    id="$(plutil -extract id raw -o - "$result")" || id=""
    [ -z "$id" ] || xcrun notarytool log "$id" \
      --key "$API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" >&2 || true
    die "notarization of $(basename "$1") ended as $status"
  fi
}

# ── Server ────────────────────────────────────────────────────────────────────
build_server() {
  local server="$ROOT/djukebox_server" name="djukebox-server-macos-$VERSION"
  local stage="$DIST/$name" products f
  local arch_flags=(--arch arm64 --arch x86_64)
  . "$server/scripts/server_payload.sh"

  step "Building the server $VERSION (arm64 + x86_64)"
  if ! swift build -c release --package-path "$server" "${arch_flags[@]}"; then
    echo "WARNING: the universal build failed; BUILDING ARM64 ONLY." >&2
    echo "WARNING: this server will not run on an Intel Mac." >&2
    arch_flags=(--arch arm64)
    swift build -c release --package-path "$server" "${arch_flags[@]}"
  fi
  products="$(swift build -c release --package-path "$server" "${arch_flags[@]}" --show-bin-path)"

  step "Packaging $name"
  rm -rf "$stage" "$stage.tar.gz"
  mkdir -p "$stage/scripts" "$stage/launchd"
  server_payload_stage "$products" "$stage/bin"
  cp "$server/$SERVER_PAYLOAD_TEMPLATE" "$stage/$SERVER_PAYLOAD_TEMPLATE"
  for f in $SERVER_PAYLOAD_SCRIPTS; do
    cp "$server/$f" "$stage/$f"
  done
  echo "architectures: $(xcrun lipo -archs "$stage/bin/Run")"

  if [ "$UNSIGNED" -eq 1 ]; then
    echo "WARNING: --unsigned: ad hoc signature, not notarized. Not for release." >&2
    server_payload_sign "$stage/bin" -
  else
    server_payload_sign "$stage/bin" "$IDENTITY" --options runtime --timestamp
    codesign --verify --strict --verbose=2 "$stage/bin/Run"
    # notarytool takes no tarballs, and a bare binary cannot be stapled:
    # Gatekeeper looks the ticket up online.
    ditto -c -k --keepParent "$stage" "$WORK/$name.zip"
    notarize "$WORK/$name.zip"
  fi

  COPYFILE_DISABLE=1 tar -czf "$stage.tar.gz" -C "$DIST" "$name"
  echo "wrote $stage.tar.gz"
}

# ── Mac app ───────────────────────────────────────────────────────────────────
build_mac() {
  local archive="$DIST/DJukeboxMac-$VERSION.xcarchive" export_dir="$WORK/mac-export"
  local options="$WORK/MacExportOptions.plist" dmg="$DIST/DJukebox-$VERSION.dmg" app

  step "Archiving the Mac app $VERSION ($BUILD)"
  rm -rf "$archive" "$dmg"
  xcodebuild archive \
    -project "$MAC_PROJECT" \
    -scheme DJukebox \
    -archivePath "$archive" \
    -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM"

  cat > "$options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$IDENTITY</string>
</dict>
</plist>
EOF
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$options"
  app="$(find "$export_dir" -maxdepth 1 -name '*.app' | head -1)"
  [ -n "$app" ] || die "no .app was exported"

  ditto -c -k --keepParent "$app" "$WORK/DJukebox-app.zip"
  notarize "$WORK/DJukebox-app.zip"
  xcrun stapler staple "$app"
  spctl --assess --type execute --verbose=2 "$app"

  step "Creating $(basename "$dmg")"
  hdiutil create -volname DJukebox -srcfolder "$app" -ov -format UDZO "$dmg"
  codesign --force --sign "$IDENTITY" --timestamp "$dmg"
  notarize "$dmg"
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
  echo "wrote $dmg"
}

# ── iOS app ───────────────────────────────────────────────────────────────────
# Automatic signing with the App Store Connect key; no Developer ID involved.
build_ios() {
  if ! load_api_key; then
    echo ""
    echo "SKIP: iOS archive and TestFlight upload: set APPLE_API_KEY_ID, APPLE_API_ISSUER_ID"
    echo "      and APPLE_API_KEY_PATH or APPLE_API_KEY_P8_BASE64."
    return 0
  fi
  local archive="$DIST/DJukeboxiOS-$VERSION.xcarchive" options="$WORK/IOSExportOptions.plist" team
  team="$(team_id "$IOS_PROJECT")"
  local auth=(-allowProvisioningUpdates
    -authenticationKeyPath "$API_KEY"
    -authenticationKeyID "$APPLE_API_KEY_ID"
    -authenticationKeyIssuerID "$APPLE_API_ISSUER_ID")

  step "Archiving the iOS app $VERSION ($BUILD)"
  rm -rf "$archive"
  xcodebuild archive \
    -project "$IOS_PROJECT" \
    -scheme DJukeboxiOS \
    -archivePath "$archive" \
    -destination 'generic/platform=iOS' \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$team" \
    "${auth[@]}"

  cat > "$options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>teamID</key>
    <string>$team</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
EOF
  step "Uploading to TestFlight"
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$WORK/ios-export" \
    -exportOptionsPlist "$options" \
    "${auth[@]}"
  echo "wrote $archive and uploaded it"
}

# credentials are checked before any long build starts
if [ "$DO_MAC" -eq 1 ] || { [ "$DO_SERVER" -eq 1 ] && [ "$UNSIGNED" -eq 0 ]; }; then
  need_developer_id
fi
# plain if blocks: calling these from an && list would switch off set -e in them
if [ "$DO_SERVER" -eq 1 ]; then build_server; fi
if [ "$DO_MAC" -eq 1 ]; then build_mac; fi
if [ "$DO_IOS" -eq 1 ]; then build_ios; fi

step "Done: $DIST"
