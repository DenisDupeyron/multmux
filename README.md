# `multmux`

~~A multi-dimensional tmux-in-tmux session multiplexer giving you multiple isolated sessions in one infinitely configurable and extensible layout.~~

~~A proof you can write clean and compact code in Bash.~~

A wrapper that will make you feel like a `tmux` wizard with only two shortcuts.

With the provided default `tmux` config, click on a line separator to resize panes, click in a pane to select/activate it. Then:
- `ctrl+b z` to zoom in and out of a pane
- `ctrl+a s` then up and down arrow and hit `return` on the session you want to select for the main pane (you may need to click on the main pane to activate it first)

> [!CAUTION]
> If the mouse or shortcuts above don't work, it's most likely because you have a broken `tmux.conf`. You can fix it, but we recommend you use [the bundled one](https://github.com/DenisDupeyron/multmux/blob/main/defaults/tmux.conf) (it's only installed automatically if there is no pre-existing one).

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

## What it does

`multmux` creates a `tmux` layout with:

- A **main pane** (left, 60% width by default) running multiple inner sessions you can switch between using standard `tmux` shortcuts
- **Overflow panes** (right, stacked vertically, 3 by default) for monitoring, quick commands, etc., which persist across session switches

Neither socket uses the default `tmux` socket, so your regular `tmux` usage is completely unaffected.

## Usage

```bash
multmux start [--no-attach]   # Start multmux (idempotent)
multmux stop                  # Stop all sessions (asks for confirmation)
multmux add                   # Add a new inner session and switch to it
multmux remove                # Remove current inner session
multmux list                  # List inner sessions
multmux update                # Update multmux to the latest version
multmux help                  # Show help
```

All commands work from any context: a separate terminal, an overflow pane, or from within an inner session.

### `start`

Creates the outer layout and inner sessions. If already running, attaches to the existing instance. Use `--no-attach` to create in the background.

### `stop`

Asks for confirmation, then kills all inner sessions and the outer session.

### `update`

Re-runs the install script to fetch the latest `multmux` script from GitHub. Your config at `~/.config/multmux.conf` and `tmux.conf` are left untouched since the installer only writes them if they do not already exist.

### `add` / `remove`

`add` creates a new inner session and switches to it immediately.

`remove` kills the current inner session and switches to the previous one. If it's the last session, a fresh replacement is created automatically (the main pane is never left empty).

## Configuration

Configuration lives at `~/.config/multmux.conf` (a sourced bash file):

```bash
# The initial directory for each pane or session
START_DIR="${HOME}"

# Main pane width (columns or percentage)
MAIN_PANE_WIDTH="60%"

# Number of overflow panes stacked vertically on the right side
OVERFLOW_PANES=3

# Number of inner sessions in the main pane (maximum 99)
INNER_SESSIONS=10

# Base tmux config applied to both outer and inner sessions
BASE_CONF=$(cat << 'EOF'
EOF
)

# Additional config for the outer session only
OUTER_CONF=$(cat << 'EOF'
set -g status off
EOF
)

# Additional config for the inner sessions only
INNER_CONF=$(cat << 'EOF'
set -g status-left "#S"
set -g status-right ""
set -g window-status-format ""
set -g window-status-current-format ""
set -g status-left-length 80
set -g status on
EOF
)
```

The `tmux` config blocks use standard `tmux` syntax, just paste your settings between the `EOF` markers.

## Uninstall

```bash
rm ~/.local/bin/multmux
rm ~/.config/multmux.conf        # if you want to remove the config too
rm -rf ~/.cache/multmux
```

## Architecture

```
Terminal
└── tmux (socket: multmux-outer)
    ├── Pane 0 (main, left 60%)
    │   └── tmux attach (socket: multmux-inner)
    │       ├── session-01
    │       ├── session-02
    │       ├── ...
    │       └── session-10
    ├── Pane 1 (overflow)
    ├── Pane 2 (overflow)
    └── Pane 3 (overflow)
```

Two sockets ensure:
1. No infinite nesting: outer and inner are completely isolated
2. No conflict with the user's own `tmux` sessions (default socket untouched)
3. Commands like `multmux stop` can safely kill one server without affecting the other or the user's sessions
