#!/bin/bash
# Triggers the GitHub Actions release by tagging HEAD as release/<version> and
# pushing the tag. .github/workflows/release.yml runs on those tags, and its
# release-publish job opens a DRAFT GitHub Release, which still has to be
# published by hand on github.com.
#
# A manual `workflow_dispatch` run on a branch is not a substitute: it builds,
# but publishes nothing.
#
# This script does no building. It takes no arguments: the version comes from
# scripts/version.sh, so the tag, release name and file names cannot disagree.

set -e
set -o pipefail

if [ "$#" -gt 0 ]; then
    echo "ERROR: this script takes no arguments; the tag is derived from scripts/version.sh."
    echo "       To release a different version, bump the version constant in"
    echo "       DJukeboxCommon/Sources/DJukeboxCommon/Version.swift (and MARKETING_VERSION"
    echo "       in both Xcode projects) and commit that first."
    exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")"

# ── Version and commit ────────────────────────────────────────────────────────
if ! VERSION=$(scripts/version.sh); then
    echo "ERROR: could not read the version with scripts/version.sh"
    exit 1
fi
GIT_HASH=$(git rev-parse HEAD)
TAG="release/${VERSION}"

echo "==> DJukebox ${VERSION}  commit ${GIT_HASH}"
echo "==> Tag: ${TAG}"

# ── Refuse to re-tag ──────────────────────────────────────────────────────────
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    echo "ERROR: tag '${TAG}' already exists locally (at $(git rev-parse --short "${TAG}^{commit}"))."
    echo "       Bump the version in DJukeboxCommon/Sources/DJukeboxCommon/Version.swift,"
    echo "       or delete the tag: git tag -d ${TAG} && git push origin :refs/tags/${TAG}"
    exit 1
fi
# ls-remote exits 0 when the tag is found and 2 when it isn't, but it also exits
# nonzero (128) when it can't reach origin. Keep the three cases apart, or an
# unreachable origin looks exactly like "tag is free".
set +e
git ls-remote --exit-code --tags origin "${TAG}" >/dev/null 2>&1
LS_REMOTE_RC=$?
set -e
case "$LS_REMOTE_RC" in
    0)
        echo "ERROR: tag '${TAG}' already exists on origin. That version is already released."
        echo "       Bump the version in DJukeboxCommon/Sources/DJukeboxCommon/Version.swift."
        exit 1
        ;;
    2)
        : # no such tag on origin
        ;;
    *)
        echo "WARNING: could not reach origin to check for an existing '${TAG}'"
        echo "         (git ls-remote exited ${LS_REMOTE_RC})."
        echo "         Continuing -- the push below will fail if it is already taken."
        ;;
esac

# ── Warn about anything the tagged commit won't contain ───────────────────────
if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "WARNING: working tree has uncommitted changes; the tag points at"
    echo "         ${GIT_HASH} without them."
fi

# A commit that is on no remote branch is reachable only from the tag, and the
# generated release notes come out empty.
if ! git branch -r --contains HEAD 2>/dev/null | grep . >/dev/null; then
    echo "WARNING: HEAD is not on any remote branch. Push your branch first so the"
    echo "         release notes generate against real history:  git push"
fi

# ── Tag and push ──────────────────────────────────────────────────────────────
echo ""
echo "==> Tagging ${GIT_HASH} as '${TAG}'..."
git tag -a "$TAG" "$GIT_HASH" -m "Release ${VERSION}"

echo "==> Pushing '${TAG}' to origin..."
# Roll the local tag back on a failed push, so a retry isn't blocked by the
# local-tag guard above.
if ! git push origin "refs/tags/${TAG}"; then
    echo ""
    echo "ERROR: push failed; removing the local tag '${TAG}' so you can retry."
    git tag -d "$TAG"
    exit 1
fi

echo ""
echo "==> Pushed ${TAG}. GitHub Actions is now building the release."
echo "    Runs:   https://github.com/brianm998/djukebox/actions"
echo "    Drafts: https://github.com/brianm998/djukebox/releases"
echo ""
echo "    The release is created as a DRAFT once every build job passes; publish it"
echo "    by hand when the artifacts look right."
