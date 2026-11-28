# What a runnable server is made of. Sourced by install_launch_agent.sh and by
# release_darwin.sh, so the file list lives only here.
# bash 3.2 compatible; defines names and functions, does nothing else.

# shipped in the release tarball beside bin/, relative to djukebox_server/
SERVER_PAYLOAD_TEMPLATE=launchd/com.brianm998.djukebox.plist.template
SERVER_PAYLOAD_SCRIPTS="scripts/install_launch_agent.sh scripts/uninstall_launch_agent.sh scripts/server_payload.sh"
SERVER_PAYLOAD_DYLIB=libswiftCompatibilitySpan.dylib

# server_payload_copy SRC DEST_DIR
# Replaces rather than overwrites: macOS kills a signed binary rewritten in place.
server_payload_copy() {
  local dest="$2/$(basename "$1")"
  rm -rf "$dest" && cp -R "$1" "$dest" || { echo "error: copy of $1 failed" >&2; return 1; }
}

# server_payload_stage BIN_DIR OUT_DIR [prebuilt]
# Copies Run, its resource bundles and the Swift compatibility dylib from BIN_DIR
# into OUT_DIR. With "prebuilt", BIN_DIR is already a complete payload and no
# developer tool is used (a Mac without Xcode can install it).
server_payload_stage() {
  local src="$1" out="$2" prebuilt="${3:-}" b usr span
  [ -x "$src/Run" ] || { echo "error: no Run binary in $src" >&2; return 1; }
  mkdir -p "$out" || return 1
  server_payload_copy "$src/Run" "$out" || return 1
  for b in "$src"/*.bundle; do
    [ -e "$b" ] || continue
    server_payload_copy "$b" "$out" || return 1
  done
  if [ -f "$src/$SERVER_PAYLOAD_DYLIB" ]; then
    server_payload_copy "$src/$SERVER_PAYLOAD_DYLIB" "$out" || return 1
  elif [ "$prebuilt" != prebuilt ] && xcrun otool -L "$src/Run" | grep "$SERVER_PAYLOAD_DYLIB" >/dev/null; then
    usr="$(dirname "$(dirname "$(xcrun --find swift)")")"
    span="$usr/lib/swift-5.5/macosx/$SERVER_PAYLOAD_DYLIB"
    [ -f "$span" ] || span="$(find "$usr/lib" -path '*macosx*' -name "$SERVER_PAYLOAD_DYLIB" 2>/dev/null | head -1)"
    if [ -z "$span" ] || [ ! -f "$span" ]; then
      echo "error: Run links $SERVER_PAYLOAD_DYLIB but it was not found in the toolchain" >&2
      return 1
    fi
    server_payload_copy "$span" "$out" || return 1
  fi
  # A universal build has no rpath to its own directory, and the dylib is weakly
  # linked, so without one it is silently not loaded. This voids the signature:
  # callers sign afterwards.
  if [ "$prebuilt" != prebuilt ] && [ -f "$out/$SERVER_PAYLOAD_DYLIB" ] \
      && ! xcrun otool -l "$out/Run" | grep ' path @loader_path (' >/dev/null; then
    xcrun install_name_tool -add_rpath @loader_path "$out/Run" || { echo "error: cannot add an rpath to Run" >&2; return 1; }
  fi
}

# server_payload_sign DIR IDENTITY [codesign options...]
# Signs the dylibs and bundles in DIR, then Run.
server_payload_sign() {
  local dir="$1" identity="$2" f
  shift 2
  for f in "$dir"/*.dylib "$dir"/*.bundle; do
    [ -e "$f" ] || continue
    codesign --force --sign "$identity" "$@" "$f" || { echo "error: codesign failed for $f" >&2; return 1; }
  done
  codesign --force --sign "$identity" "$@" --identifier com.brianm998.djukebox.server "$dir/Run" \
    || { echo "error: codesign failed for $dir/Run" >&2; return 1; }
}
