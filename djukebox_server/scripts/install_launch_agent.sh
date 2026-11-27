#!/bin/bash
# Install (or upgrade) the djukebox server as a per-user launch agent.
# bash 3.2 compatible. See LAUNCH_AGENT.md.
set -u

LABEL=com.brianm998.djukebox
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SERVER_DIR/launchd/$LABEL.plist.template"

DB="$SERVER_DIR/db.sqlite"
MUSIC_DIR=/qp/mp3/
HISTORY_DIR=/qp/mp3/playing_history
PORT=8080
IDENTITY=-
NEW_DB=0
DRY_RUN=""

usage() {
  echo "usage: $0 [--db FILE] [--music-dir DIR] [--history-dir DIR] [--port N]"
  echo "          [--sign-identity ID] [--new-db] [--dry-run DIR]"
}
die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --db) [ $# -ge 2 ] || die "--db needs a value"; DB="$2"; shift 2;;
    --music-dir) [ $# -ge 2 ] || die "--music-dir needs a value"; MUSIC_DIR="$2"; shift 2;;
    --history-dir) [ $# -ge 2 ] || die "--history-dir needs a value"; HISTORY_DIR="$2"; shift 2;;
    --port) [ $# -ge 2 ] || die "--port needs a value"; PORT="$2"; shift 2;;
    --sign-identity) [ $# -ge 2 ] || die "--sign-identity needs a value"; IDENTITY="$2"; shift 2;;
    --new-db) NEW_DB=1; shift;;
    --dry-run) [ $# -ge 2 ] || die "--dry-run needs a directory"; DRY_RUN="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) usage >&2; die "unknown option: $1";;
  esac
done

[ "$(id -u)" -ne 0 ] || die "do not run as root; the agent is per-user"
case "$PORT" in ''|*[!0-9]*) die "--port must be a number";; esac
[ -f "$TEMPLATE" ] || die "missing template $TEMPLATE"

# make a path absolute without requiring it to exist
abspath() {
  case "$1" in
    /*) echo "$1";;
    "~"/*) echo "$HOME/${1#"~"/}";;
    *) echo "$PWD/$1";;
  esac
}
DB="$(abspath "$DB")"
MUSIC_DIR="$(abspath "$MUSIC_DIR")"
HISTORY_DIR="$(abspath "$HISTORY_DIR")"

if [ ! -f "$DB" ] && [ "$NEW_DB" -ne 1 ]; then
  die "database $DB does not exist. Pass --db to point at the real one, or --new-db to start empty."
fi

INSTALL_DIR="$HOME/Library/Application Support/DJukebox"
BIN_DIR="$INSTALL_DIR/bin"
BINARY="$BIN_DIR/Run"
LOG_DIR="$HOME/Library/Logs/djukebox"
LOG_PATH="$LOG_DIR/server.log"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# render_plist OUTFILE
render_plist() {
  local out="$1" i=0
  cp "$TEMPLATE" "$out" || die "cannot write $out"
  set_key() { /usr/libexec/PlistBuddy -c "Set :$1 $2" "$out" || die "PlistBuddy failed for $1"; }
  # PlistBuddy treats the value as the rest of the line, so spaces are fine.
  # Values with XML characters are escaped by PlistBuddy itself on save.
  set_key "ProgramArguments:0" "$BINARY"
  set_key "ProgramArguments:5" "$PORT"
  set_key "EnvironmentVariables:DJUKEBOX_MUSIC_DIR" "$MUSIC_DIR"
  set_key "EnvironmentVariables:DJUKEBOX_HISTORY_DIR" "$HISTORY_DIR"
  set_key "EnvironmentVariables:DJUKEBOX_DB_PATH" "$DB"
  set_key "WorkingDirectory" "$INSTALL_DIR"
  set_key "StandardOutPath" "$LOG_PATH"
  set_key "StandardErrorPath" "$LOG_PATH"
}

if [ -n "$DRY_RUN" ]; then
  [ -d "$DRY_RUN" ] || die "--dry-run directory $DRY_RUN does not exist"
  OUT="$DRY_RUN/$LABEL.plist"
  render_plist "$OUT"
  plutil -lint "$OUT" >/dev/null || die "rendered plist is invalid"
  echo "dry run: wrote $OUT"
  echo "would: swift build -c release --package-path $SERVER_DIR"
  echo "would: boot out gui/$(id -u)/$LABEL if loaded; stop if port $PORT is in use"
  echo "would: copy Run, *.bundle, libswiftCompatibilitySpan.dylib to $BIN_DIR and codesign (identity: $IDENTITY)"
  echo "would: install plist to $PLIST, bootstrap it, wait for port $PORT"
  echo "database: $DB"
  echo "music dir: $MUSIC_DIR"
  exit 0
fi

DOMAIN="gui/$(id -u)"
SVC="$DOMAIN/$LABEL"
is_loaded() { launchctl print "$SVC" >/dev/null 2>&1; }
port_listener() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -Fpc 2>/dev/null; }

# 1. build
swift build -c release --package-path "$SERVER_DIR" || die "build failed; installed agent (if any) left as it is"
PRODUCTS="$(swift build -c release --package-path "$SERVER_DIR" --show-bin-path)" || die "cannot find build products"
[ -x "$PRODUCTS/Run" ] || die "no Run binary in $PRODUCTS"

# 2. stop a loaded agent
WAS_LOADED=0
if is_loaded; then
  WAS_LOADED=1
  launchctl bootout "$SVC" || true
  n=0
  while is_loaded && [ $n -lt 30 ]; do sleep 1; n=$((n+1)); done
  is_loaded && die "agent did not unload"
fi

# 3. is the port free?
L="$(port_listener)"
if [ -n "$L" ]; then
  PID="$(echo "$L" | sed -n 's/^p//p' | head -1)"
  CMD="$(ps -o command= -p "$PID" 2>/dev/null)"
  echo "error: port $PORT is already in use by pid $PID: $CMD" >&2
  echo "Stop that server first (it is not killed for you)." >&2
  if [ "$WAS_LOADED" -eq 1 ] && [ -f "$PLIST" ]; then
    echo "reloading the previous agent" >&2
    launchctl bootstrap "$DOMAIN" "$PLIST" || echo "warning: could not reload previous agent" >&2
  fi
  exit 1
fi

# 4. copy
mkdir -p "$BIN_DIR" || die "cannot create $BIN_DIR"
cp -f "$PRODUCTS/Run" "$BINARY" || die "copy of Run failed"
for b in "$PRODUCTS"/*.bundle; do
  [ -e "$b" ] || continue
  rm -rf "$BIN_DIR/$(basename "$b")"
  cp -R "$b" "$BIN_DIR/" || die "copy of $b failed"
done
if otool -L "$BINARY" | grep -q libswiftCompatibilitySpan; then
  TOOLCHAIN_USR="$(dirname "$(dirname "$(xcrun --find swift)")")"
  SPAN="$TOOLCHAIN_USR/lib/swift-5.5/macosx/libswiftCompatibilitySpan.dylib"
  [ -f "$SPAN" ] || SPAN="$(find "$TOOLCHAIN_USR/lib" -name libswiftCompatibilitySpan.dylib 2>/dev/null | head -1)"
  if [ -n "$SPAN" ] && [ -f "$SPAN" ]; then
    cp -f "$SPAN" "$BIN_DIR/" || die "copy of libswiftCompatibilitySpan.dylib failed"
  else
    echo "warning: binary links libswiftCompatibilitySpan.dylib but it was not found in the toolchain" >&2
  fi
fi

# 5. sign
for f in "$BIN_DIR"/*.dylib "$BIN_DIR"/*.bundle; do
  [ -e "$f" ] || continue
  codesign --force --sign "$IDENTITY" "$f" || die "codesign failed for $f"
done
codesign --force --sign "$IDENTITY" --identifier com.brianm998.djukebox.server "$BINARY" || die "codesign failed"

# 6. plist and bootstrap
mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents" || die "cannot create directories"
render_plist "$PLIST"
plutil -lint "$PLIST" >/dev/null || die "installed plist is invalid"
ok=0; n=0
while [ $n -lt 10 ]; do
  if launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null; then ok=1; break; fi
  sleep 1; n=$((n+1))
done
if [ $ok -ne 1 ]; then launchctl bootstrap "$DOMAIN" "$PLIST"; die "launchctl bootstrap failed"; fi

# 7. wait for the port
n=0
while [ $n -lt 60 ]; do
  if [ -n "$(port_listener)" ]; then
    echo "djukebox agent installed and listening on port $PORT"
    echo "log: $LOG_PATH"
    exit 0
  fi
  sleep 1; n=$((n+1))
done
echo "error: agent did not start listening on port $PORT within 60s. Last log lines:" >&2
tail -n 20 "$LOG_PATH" >&2
exit 1
