#!/bin/bash
# s1282: an offline relaunch restores the saved local queue.
set -euo pipefail
cd "$(dirname "$0")/../.."

fail() { echo "s1282: $*" >&2; exit 1; }

source=DJukeboxClient/Sources/TrackFetcher.swift
grep -qF 'PlayingQueueType!' "$source" && fail "$source: implicitly unwrapped queueType"
grep -qF 'as! AudioTrack' "$source" && fail "$source: forced AudioTrack cast"

swift test --package-path DJukeboxClient --filter RestoreStateTests

echo "s1282: ok"
