# `multmux`

~~A multi-dimensional tmux-in-tmux session multiplexer giving you multiple isolated sessions in one infinitely configurable and extensible layout.~~

~~A proof you can write clean and compact code in Bash.~~

A wrapper that will make you feel like a `tmux` wizard with only two shortcuts.

With the bundled `tmux` config, click on a line separator to resize panes, click in a pane to select/activate it. Then:
- `ctrl+b z` to zoom in and out of a pane
- `ctrl+a s` then up and down arrow and hit `return` on the session you want to select for the main pane (you may need to click on the main pane to activate it first)

## One-liner install

```bash
curl -fsSL https://raw.githubusercontent.com/DenisDupeyron/multmux/main/install.sh | bash
```

Or:

```bash
wget -qO- https://raw.githubusercontent.com/DenisDupeyron/multmux/main/install.sh | bash
```

### Requirements

- `bash` >= 4
- `tmux` >= 3.2
- `curl` or `wget`

### Shell completion

Bash and zsh completion for `multmux`'s subcommands is installed automatically
to `~/.local/share/bash-completion/completions/multmux` and
`~/.local/share/zsh/site-functions/_multmux`. The installer checks whether your
shell will actually pick the file up and, on every install and update, prints
what to add to your shell profile if not.

On Oh My Zsh, the `fpath` line the installer asks you to add must go **before**
`source $ZSH/oh-my-zsh.sh`, since that's where Oh My Zsh calls `compinit`
internally. Adding it after (e.g. at the bottom of `~/.zshrc`, the natural
place to append something) silently does nothing.

## What it does

`multmux` creates a `tmux` layout with:

- A **main pane** (left, 60% width by default) running multiple inner sessions you can switch between using standard `tmux` shortcuts
- **Overflow panes** (right, stacked vertically, 3 by default) for monitoring, quick commands, etc., which persist across session switches

Neither socket uses the default `tmux` socket, so your regular `tmux` usage is completely unaffected.

## Usage

```bash
multmux start [--no-attach]   # Start multmux (idempotent)
multmux stop                  # Stop all sessions (asks for confirmation)
multmux attach                # Attach to the outer session (idempotent)
multmux detach                # Detach from multmux, from anywhere (idempotent)
multmux add [path]            # Add a new inner session (default: START_DIR) and switch to it
multmux remove                # Remove the current inner session
multmux rename <name>         # Rename the current inner session
multmux status                # Show outer/inner running state and inner sessions
multmux reset-layout          # Reset outer pane geometry to configured sizes
multmux update [--dry-run]    # Update multmux to the latest version
multmux uninstall [--config]  # Remove multmux files (asks for confirmation)
multmux help                  # Show help
```

All commands work from any context: a separate terminal, an overflow pane, or from within an inner session.

### `start`

Creates the outer layout and inner sessions. If already running, attaches to the existing instance. Use `--no-attach` to create in the background.

### `stop`

Asks for confirmation, then kills all inner sessions and the outer session.

### `attach` / `detach`

`attach` attaches to the outer session, from anywhere. It's a no-op if you're already attached.

`detach` detaches your terminal from the outer session, from anywhere (a separate terminal, an overflow pane, or an inner session). It's a no-op if you're not attached.

### `uninstall`

`uninstall` asks for confirmation and removes the multmux executable, cache, and shell completions. Pass `--config` to also remove `~/.config/multmux.conf`. After removal, it prints the one-line install command.

### `update`

`start` checks for a newer version in the background, at most once every `AUTO_UPDATE_CHECK_INTERVAL_DAYS`. If `AUTO_UPDATE` is true (default), it installs automatically. Otherwise it just leaves a notice.

`update` re-runs the install script regardless of version. It adds newly required top-level settings from the current defaults to your config and warns about missing tmux settings in user-owned blocks.

`update --dry-run` checks immediately and only reports. It never installs.

### `add` / `remove`

`add` creates a new inner session, in `path` if given or `START_DIR` otherwise, and switches to it immediately.

`remove` kills the current inner session and switches to the previous one. If it's the last session, a fresh replacement is created automatically (the main pane is never left empty).

### `rename`

Renames the current inner session. Rejects empty names, names already in use, and names containing `:` or `.` (reserved by tmux for `session:window.pane` targets).

Once renamed this way, the session stops following its working directory until multmux is restarted.

### `status`

Reports whether the outer and inner sockets are running, and if the inner one is,
lists its sessions with the currently active one marked. Never fails just because
multmux isn't running — it tells you that instead.

### `reset-layout`

Re-applies the configured `MAIN_PANE_WIDTH` and `main-vertical` layout, e.g. after manual pane dragging. Focus is left untouched.

## Session naming

Inner sessions are named after their current directory, and automatically renamed whenever you `cd`:

- Your home directory is shown as `~` (a session in your home directory itself is named `~/`, not a bare `~`, since tmux reserves the exact string `~` for its own "marked pane" target syntax).
- Any single path component longer than `SESSION_NAME_COMPONENT_MAX` (default 20) is truncated in its own middle, with an ellipsis (e.g. `a-really-long-directory-name` → `a-really-l…tory-name`).
- If the whole name is still longer than `SESSION_NAME_TOTAL_MAX` (default 60) after that, whole components are dropped from the left and replaced with a single leading ellipsis (e.g. `~/work/clients/acme/backend/services/billing` → `…/backend/services/billing`).
- If two sessions would end up with the same name, the newer one gets `-1`, `-2`, etc. appended (lowest available number, reused when a session is removed).
- `:` and `.` are replaced (tmux reserves them for `session:window.pane` targets). This only applies to automatic renaming, since `rename` rejects them outright instead (see above).

Renaming a session manually with `multmux rename` makes it stop following its directory.

## Configuration

Configuration lives at `~/.config/multmux.conf`, a sourced bash file created from
[`defaults/multmux.conf`](defaults/multmux.conf) on first install. It sets:

- `START_DIR`, `MAIN_PANE_WIDTH`, `OVERFLOW_PANES`, `INNER_SESSIONS`: the layout described above
- `SESSION_NAME_COMPONENT_MAX`, `SESSION_NAME_TOTAL_MAX`: see [Session naming](#session-naming)
- `AUTO_UPDATE_CHECK_INTERVAL_DAYS`, `AUTO_UPDATE`: see [`update`](#update)
- `BASE_CONF`, `OUTER_CONF`, `INNER_CONF`: the `tmux` config applied to both sockets, the
  outer session only, and the inner sessions only, respectively (standard `tmux` syntax,
  see [`defaults/multmux.conf`](defaults/multmux.conf) for the full bundled config with
  comments. Paste your own settings between the `EOF` markers of each block)

`multmux update` adds missing required top-level settings from the current defaults and reports the change. It also warns about tmux directives in the bundled config that your user-owned blocks do not contain. Runtime commands only validate the file and never modify it.

## Uninstall

```bash
multmux uninstall
```

Pass `--config` to remove `~/.config/multmux.conf` too:

```bash
multmux uninstall --config
```

## Architecture

```
Terminal
└── tmux (socket: multmux-outer)
    ├── Pane 0 (main, left 60%)
    │   └── tmux attach (socket: multmux-inner)
    │       ├── ~/ (named after its cwd, see Session naming)
    │       ├── ~/-1
    │       ├── ...
    │       └── ~/-9
    ├── Pane 1 (overflow)
    ├── Pane 2 (overflow)
    └── Pane 3 (overflow)
```

Two sockets ensure:
1. No infinite nesting: outer and inner are completely isolated
2. No conflict with the user's own `tmux` sessions (default socket untouched)
3. Commands like `multmux stop` can safely kill one server without affecting the other or the user's sessions

## Development

The socket names (`multmux-outer`/`multmux-inner`) can be overridden with environment
variables, useful for testing without touching a real, running multmux session:

```bash
MULTMUX_OUTER_SOCKET=multmux-outer-test MULTMUX_INNER_SOCKET=multmux-inner-test ./multmux
```

### Running the tests

The test suite uses [bats-core](https://github.com/bats-core/bats-core):

```bash
bats tests/unit          # pure-logic tests, no tmux, fast
bats tests/integration   # real tmux against throwaway sockets/config, slower
bats tests/unit tests/integration   # everything
```

See `tests/README.md` for what each suite covers and the specific failure modes tested.
