# Running the server as a launch agent

The server can run as a per-user launch agent (`com.brianm998.djukebox`) that
starts when you log in, instead of running `run_wifi_server.sh` by hand.

The installer builds the server once (release), copies the binary to
`~/Library/Application Support/DJukebox/bin`, signs it, writes
`~/Library/LaunchAgents/com.brianm998.djukebox.plist` and loads it. A branch
switch or `swift build` in a checkout does not change what the agent runs.

## Install

1. **Stop the hand-started server first.** While the agent is installed,
   `run_wifi_server.sh` cannot also use port 8080. The installer refuses to
   continue (and does not kill anything) if something listens on the port.
2. **Run the installer from the main checkout**, the one holding the real
   `djukebox_server/db.sqlite`:

   ```
   djukebox_server/scripts/install_launch_agent.sh
   ```

   The database stays where it is (it is not copied), so that checkout must
   not be moved or deleted. A missing database is an error unless you pass
   `--new-db`.

### From a release tarball

No Xcode or checkout is needed:

```
tar -xzf djukebox-server-macos-<version>.tar.gz
djukebox-server-macos-<version>/scripts/install_launch_agent.sh \
    --music-dir /path/to/music --history-dir /path/to/music/playing_history --new-db
```

The installer sees `bin/Run` beside `scripts/`, skips the build and keeps the
release signatures. The default database is
`~/Library/Application Support/DJukebox/db.sqlite`; leave `--new-db` off once it
exists, and pass `--db` to keep using a database from a checkout. To try the
server without installing it, run
`djukebox-server-macos-<version>/bin/Run serve -H 0.0.0.0 -p 8080` with
`DJUKEBOX_MUSIC_DIR` and `DJUKEBOX_DB_PATH` set.

Options: `--db`, `--music-dir` (default `/qp/mp3/`), `--history-dir`
(default `/qp/mp3/playing_history`), `--port` (8080), `--sign-identity`
(default for a source install `-`, ad hoc; a tarball install does not re-sign
unless this is given), `--prebuilt DIR` (install `DIR/bin` without building),
`--new-db`, `--dry-run DIR` (only writes the plist into
`DIR`; no build, no launchctl).

The agent sets `DJUKEBOX_REQUIRE_MUSIC_DIR=1`: if the music directory is
missing or empty (for example the USB volume is not mounted yet at login) the
server logs the path and exits non-zero, and launchd retries every 10 seconds.

## Upgrade

Pull/update the checkout and run the installer again. It is safe to repeat; it
rebuilds, unloads the old agent, replaces the binary and loads it again.

## Status, restart, logs

```
launchctl print gui/$(id -u)/com.brianm998.djukebox
launchctl kickstart -k gui/$(id -u)/com.brianm998.djukebox
tail -f ~/Library/Logs/djukebox/server.log
```

The log is **not rotated**; trim or delete it occasionally.

## Uninstall / going back to running by hand

```
djukebox_server/scripts/uninstall_launch_agent.sh
```

This boots out the agent and removes the plist and the installed `bin`
directory. The database and logs are kept. Afterwards `run_wifi_server.sh`
works as before.

## macOS notes

- The first run may show prompts for **Local Network** access (Bonjour
  advertising) and for the **external volume**. A server started from Terminal
  did not need its own grants. With ad hoc signing the prompts can come back
  after a rebuild; install with `--sign-identity "<development certificate>"`
  to keep them.
- Launch agents start at **login**, not at boot.
