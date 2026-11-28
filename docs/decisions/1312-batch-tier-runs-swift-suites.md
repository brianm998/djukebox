# 1312: A landing batch runs the Swift suites over the merged tree

Task: #1338.

## Context

Landing is `mode = "direct"` and had no `[[tier]]`; the suites have no `build`.
Nothing ran over a batch's merged tree, so tasks that were green on their own
broke `develop` together (#1319 to #1323, 2026-11-27).

## Decision

1. `.mason/landing.toml` has a `batch` tier with `swift-common`, `swift-server`
   and `swift-client`.
2. `.mason/mason.toml` has an `[impact]` map. `DJukeboxCommon/**` selects all
   three (both other packages depend on it), `DJukeboxClient/**` and
   `djukebox_server/**` select their own suite, and `docs/**` and `**/*.md`
   select none.
3. `scripts/exit/**` also selects none. No suite reads those files, and an
   unmapped path selects everything, so the exit script a task adds would
   otherwise undo the narrowing.
4. Any other path (`.mason/`, the app projects, other scripts) selects all three.

## Consequences

- A batch now waits for the selected suites on a node before `develop` moves.
- The map also narrows each task's test step and `run_check`. A change that
  selects no suite closes as `untested`.
- A Markdown file inside a package still selects that package's suite, because
  matching globs add up.
