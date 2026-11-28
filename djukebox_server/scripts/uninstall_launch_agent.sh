#!/bin/bash
# Remove the djukebox launch agent. Keeps the database and logs.
set -u
LABEL=com.brianm998.djukebox
SVC="gui/$(id -u)/$LABEL"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN_DIR="$HOME/Library/Application Support/DJukebox/bin"

[ "$(id -u)" -ne 0 ] || { echo "error: do not run as root" >&2; exit 1; }

if launchctl print "$SVC" >/dev/null 2>&1; then
  launchctl bootout "$SVC" || true
  n=0
  while launchctl print "$SVC" >/dev/null 2>&1 && [ $n -lt 30 ]; do sleep 1; n=$((n+1)); done
  if launchctl print "$SVC" >/dev/null 2>&1; then echo "error: agent did not unload" >&2; exit 1; fi
fi
rm -f "$PLIST"
rm -rf "$BIN_DIR"
echo "djukebox launch agent removed."
echo "kept: the database (wherever --db pointed; by default djukebox_server/db.sqlite in your checkout,"
echo "      or $HOME/Library/Application Support/DJukebox/db.sqlite for a release tarball install)"
echo "kept: logs in $HOME/Library/Logs/djukebox"
exit 0
