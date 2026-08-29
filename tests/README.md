# multmux tests

Two kinds of tests, using [bats-core](https://github.com/bats-core/bats-core):

- **tests/unit/** — pure-logic tests. These `source` the `multmux` script
  directly (no subprocess) and call its functions with fixture inputs: the
  CWD-based session-naming pipeline (truncation, collisions, `~`
  substitution), config parsing/loading/healing, the config-drift check,
  version comparison, and the update-fetch logic (with curl/wget stubbed
  out, no real network). Fast, no tmux required.

- **tests/integration/** — real (but fully isolated) tmux. Every test gets
  its own throwaway `$HOME` and its own uniquely-named tmux `-L` sockets
  (via multmux's existing `MULTMUX_OUTER_SOCKET`/`MULTMUX_INNER_SOCKET`/
  `MULTMUX_REPO_URL` overrides), so nothing here ever touches a real
  running multmux or real GitHub. Covers the full command lifecycle
  (start/stop/attach/detach/add/remove/rename/list/reset-layout), the
  real CWD auto-rename tmux hook firing end to end, and the self-update
  pipeline against a local fake HTTP server standing in for GitHub.

## Running

```sh
bats tests/unit                 # fast, no tmux
bats tests/integration          # real tmux, slower
bats tests/unit tests/integration   # everything
```

Requires `tmux`, `curl` (for update tests), and `python3` (only for the
integration suite's local fake repo server, not for multmux itself).

## Failure modes covered

This is the actual point of the suite. Non-exhaustive list of what's
exercised:

- **Session naming**: home-directory substitution (including the `~`
  vs. bare-`~` edge case), per-component mid-string truncation (odd/even
  budget splits, 1- and 2-character maxes), whole-component dropping with
  a leading ellipsis, paths outside `$HOME`, paths that merely share a
  prefix with `$HOME` without being inside it, `:`/`.` substitution,
  symlinked and nonexistent directories, the lowest-available-suffix
  collision rule (including reusing a freed gap), and a session renaming
  itself to its own name never counting as a collision.
- **Config loading**: missing config file, missing-but-healable required
  variables (auto-healed and reported), missing variables that aren't in
  the bundled default either (hard failure), and the
  `SESSION_NAME_TOTAL_MAX >= COMPONENT_MAX + 2` validation boundary.
- **Config drift check**: real missing config lines are always caught;
  comment-only differences (any wording, indented or not) are never
  reported, even alongside genuine unrelated drift; and — the strongest
  regression test in the suite — `multmux update`'s drift check reflects
  the *freshly-installed* binary's own logic and defaults, not whatever
  this process happened to have loaded before the update ran.
- **Version/update fetching**: numeric (not lexicographic) version
  comparison, curl-then-wget fallback, both tools missing, empty/
  malformed/timed-out responses, and SIGPIPE-style failures never
  escaping as a script-ending error.
- **Lifecycle**: idempotent `start`, refusing to start from inside a
  nested tmux session, cleaning up orphaned inner sessions from a crashed
  previous run, the `stop` confirmation prompt (accepting/declining,
  case-insensitively), and every "not running yet" guard on
  attach/detach/add/remove/rename/list/reset-layout.
- **add/remove/rename**: collision-suffix assignment on `add`, removing
  down to (and safely replacing) the very last session — this caught a
  real bug where the replacement collided with the not-yet-killed
  original — the previous/next-session selection on removing a
  non-last session, rejecting reserved characters (`:`/`.`) in
  `rename`, the sticky `@multmux_renamed` flag surviving a real `cd`,
  and refusing to rename onto an existing name.
- **CWD auto-rename hook**: `_auto-rename` end to end, including a real
  `cd` in a live pane actually triggering tmux's own `window-renamed`
  hook (not just the function called directly), the sticky flag
  suppressing it, collision suffixing against a different session, and
  `status-interval 1` actually being set (the fix for the status line
  lagging behind a rename).
- **Self-update**: dry-run up-to-date/newer-available/unreachable-server
  reporting without installing anything, a real install actually landing
  the new version, never touching an existing config file, installing a
  default config only when one is missing, dying clearly with neither
  curl nor wget available, and failing cleanly when the update server is
  unreachable.
