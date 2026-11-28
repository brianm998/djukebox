# 1259: One version, defined in DJukeboxCommon

## Decision
`DJukeboxVersion.current` (DJukeboxCommon) is the version. `scripts/version.sh`
prints it for anything that is not Swift.

- The Xcode projects repeat it as `MARKETING_VERSION`, so a plain build in Xcode
  is correct; CI fails when either project disagrees with the script.
- Release builds override `MARKETING_VERSION` from the script and set
  `CURRENT_PROJECT_VERSION` to the GitHub run number.
- A release tag or dispatch input no longer chooses the version. The release fails
  if either differs from the script.

## To release
Change `Version.swift` and `MARKETING_VERSION` in both projects, commit, then run
`./release_github.sh` (see [1267](1267-release-tags.md)).
