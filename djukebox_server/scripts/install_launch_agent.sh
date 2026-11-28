#!/bin/bash
# Install (or upgrade) the djukebox server as a per-user launch agent.
# From a source checkout it builds first; from an extracted release tarball
# (bin/Run beside scripts/) it installs those files as they are.
# bash 3.2 compatible. See LAUNCH_AGENT.md.
set -u

LABEL=com.brianm998.djukebox
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SERVER_DIR/launchd/$LABEL.plist.template"

. "$SCRIPT_DIR/server_payload.sh" || exit 1

INSTALL_DIR="$HOME/Library/Application Support/DJukebox"
DB=""
MUSIC_DIR=/qp/mp3/
HISTORY_DIR=/qp/mp3/playing_history
PORT=8080
IDENTITY=""
PREBUILT=""
NEW_DB=0
DRY_RUN=""

usage() {
  echo "usage: $0 [--db FILE] [--music-dir DIR] [--history-dir DIR] [--port N]"
  echo "          [--sign-identity ID] [--new-db] [--prebuilt DIR] [--dry-run DIR]"
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
    --prebuilt) [ $# -ge 2 ] || die "--prebuilt needs a directory"; PREBUILT="$2"; shift 2;;
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
# an extracted release tarball has the binary and no sources
if [ -z "$PREBUILT" ] && [ -x "$SERVER_DIR/bin/Run" ] && [ ! -f "$SERVER_DIR/Package.swift" ]; then
  PREBUILT="$SERVER_DIR"
fi
if [ -n "$PREBUILT" ]; then
  PREBUILT="$(abspath "$PREBUILT")"
  [ -x "$PREBUILT/bin/Run" ] || die "no bin/Run in $PREBUILT"
  # not in the extracted directory, which is likely to be deleted
  [ -n "$DB" ] || DB="$INSTALL_DIR/db.sqlite"
else
  # a source install is ad hoc signed unless told otherwise
  [ -n "$IDENTITY" ] || IDENTITY=-
  [ -n "$DB" ] || DB="$SERVER_DIR/db.sqlite"
fi
DB="$(abspath "$DB")"
MUSIC_DIR="$(abspath "$MUSIC_DIR")"
HISTORY_DIR="$(abspath "$HISTORY_DIR")"

if [ ! -f "$DB" ] && [ "$NEW_DB" -ne 1 ]; then
  die "database $DB does not exist. Pass --db to point at the real one, or --new-db to start empty."
fi

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
  if [ -n "$PREBUILT" ]; then
    echo "would: install the prebuilt files in $PREBUILT/bin (no build)"
  else
    echo "would: swift build -c release --package-path $SERVER_DIR"
  fi
  echo "would: boot out gui/$(id -u)/$LABEL if loaded; stop if port $PORT is in use"
  echo "would: copy Run, *.bundle, $SERVER_PAYLOAD_DYLIB to $BIN_DIR"
  if [ -n "$IDENTITY" ]; then
    echo "would: codesign them (identity: $IDENTITY)"
  else
    echo "would: keep the signatures they came with"
  fi
  echo "would: install plist to $PLIST, bootstrap it, wait for port $PORT"
  echo "database: $DB"
  echo "music dir: $MUSIC_DIR"
  exit 0
fi

DOMAIN="gui/$(id -u)"
SVC="$DOMAIN/$LABEL"
is_loaded() { launchctl print "$SVC" >/dev/null 2>&1; }
port_listener() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -Fpc 2>/dev/null; }

# 1. build, unless the files came prebuilt
if [ -n "$PREBUILT" ]; then
  PRODUCTS="$PREBUILT/bin"
  PAYLOAD_MODE=prebuilt
else
  swift build -c release --package-path "$SERVER_DIR" || die "build failed; installed agent (if any) left as it is"
  PRODUCTS="$(swift build -c release --package-path "$SERVER_DIR" --show-bin-path)" || die "cannot find build products"
  [ -x "$PRODUCTS/Run" ] || die "no Run binary in $PRODUCTS"
  PAYLOAD_MODE=source
fi

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
server_payload_stage "$PRODUCTS" "$BIN_DIR" "$PAYLOAD_MODE" || die "copy to $BIN_DIR failed"

# 5. sign (a prebuilt payload keeps its signatures unless an identity was given)
if [ -n "$IDENTITY" ]; then
  server_payload_sign "$BIN_DIR" "$IDENTITY" || die "signing failed"
fi

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
