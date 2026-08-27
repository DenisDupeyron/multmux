# multmux

A tmux session multiplexer that gives you multiple isolated sessions in one layout, using two separate tmux sockets to prevent recursive-attach pitfalls.

## One-liner install

```bash
curl -fsSL https://raw.githubusercontent.com/DenisDupeyron/multmux/main/install.sh | bash
```

### Requirements

- **bash** >= 4
- **tmux** >= 3.2
- `curl` or `wget`

The installer checks all dependencies and fails loudly if anything is missing.

## What it does

multmux creates a tmux layout with:

- A **main pane** (left, 60% width) running multiple inner sessions you can switch between using standard tmux shortcuts
- **Overflow panes** (right, stacked vertically) for monitoring, quick commands, etc. which persist across session switches

The key insight: inner sessions run on a separate tmux socket (`multmux-inner`) from the outer layout (`multmux-outer`). This prevents the infinite-nesting problem that occurs when you attach tmux inside tmux on the same server/socket.

Neither socket uses the default tmux socket, so your regular `tmux` usage is completely unaffected.

## Usage

```bash
multmux start [--no-attach]   # Start multmux (idempotent)
multmux stop                  # Stop all sessions (asks for confirmation)
multmux add                   # Add a new inner session and switch to it
multmux delete                # Delete current inner session
multmux list                  # List inner sessions
multmux help                  # Show help
```

All commands work from any context: a separate terminal, an overflow pane, or from within an inner session.

### `start`

Creates the outer layout and inner sessions. If already running, attaches to the existing instance. Use `--no-attach` to create in the background.

### `stop`

Asks for confirmation, then kills all inner sessions and the outer session.

### `add` / `delete`

`add` creates a new inner session and switches to it immediately.

`delete` kills the current inner session and switches to the previous one. If it's the last session, a fresh replacement is created automatically (the main pane is never left empty).

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

The tmux config blocks use standard tmux syntax - just paste your settings between the `EOF` markers.

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
