# 1268: One script, `release_darwin.sh`, builds every release artifact

## Decision
- `release_darwin.sh` builds, signs, notarizes and packages the server, the Mac
  app and the iOS app, locally and in `release.yml` (one target per job). It
  runs no version-control commands; tagging stays with `release_github.sh`.
- `djukebox_server/scripts/server_payload.sh` is the only list of what a server
  consists of. `install_launch_agent.sh` and `release_darwin.sh` source it.
- The server ships as a universal tarball (arm64-only, with a loud warning, if
  the universal build fails). It is signed with the Developer ID and a zip of
  the same files is notarized; bare binaries cannot be stapled, so Gatekeeper
  checks the ticket online.
- The signing identity is looked up in the keychain; there is no identity
  secret. The Mac app and dmg are each notarized and stapled.
- iOS uses automatic signing with the App Store Connect API key and uploads to
  TestFlight (`destination=upload`). It never gets the Developer ID certificate.
- The Mac bundle id is `com.brianm998.djukebox.mac` (was `ked-to-it`). The
  sandbox container and its UserDefaults move with it: settings and any stored
  pairing token start fresh; the old data stays in
  `~/Library/Containers/ked-to-it`.
- Release signing jobs wait for the `check` job. Only a pushed `release/*` tag
  publishes, always as a draft; notes come from `releases/<version>.md` if present.

## Secrets
Used: `APPLE_CERTIFICATE_P12_BASE64` (Developer ID Application),
`APPLE_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`,
`APPLE_API_KEY_P8_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`.

No new secret is added. iOS relies on the API key being allowed to sign for
distribution (cloud signing needs the Admin role) and on an App Store Connect
app record for `com.djukebox.ios.client`. If the key cannot create a
distribution certificate, an Apple Distribution P12 secret and an import step
for the iOS job would be needed. Automatic signing on a fresh runner may also
create a new development certificate per run; revoke old ones if the account
reaches its limit.
