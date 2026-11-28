# 1267: Releases are `release/<version>` tags made by release_github.sh

## Decision
- A release is started by running `./release_github.sh`. It tags HEAD as
  `release/<version>`, taking the version from `scripts/version.sh`, and pushes
  the tag. It takes no arguments.
- `.github/workflows/release.yml` runs on `release/*` tags, fails if the tag
  suffix differs from `scripts/version.sh`, and publishes a draft release only
  from such a tag.
- Hand-made `v*` tags no longer trigger anything.

## Why
Deriving the tag from the code keeps the tag, release name and file names from
disagreeing. It matches `release_github.sh` in
nighttime_timelapse_airplane_remover.
