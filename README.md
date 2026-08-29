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
multmux add                   # Add a new inner session and switch to it
multmux remove                # Remove the current inner session
multmux rename <name>         # Rename the current inner session
multmux list                  # List inner sessions
multmux reset-layout          # Reset outer pane geometry to configured sizes
multmux check-update          # Check now whether a newer version is available
multmux update                # Update multmux to the latest version
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

### `check-update` / `update`

`start` always checks for a newer version in the background on its own, at most once every `AUTO_UPDATE_CHECK_INTERVAL_DAYS` (see below). If `AUTO_UPDATE` is true (the default), it installs the newer version right away, automatically; if false, it just leaves a one-line notice. `check-update` does the same check immediately instead of waiting for the next `start`, and reports (or installs, per `AUTO_UPDATE`) right away.

`update` unconditionally re-runs the install script to fetch the latest `multmux` script from GitHub, regardless of version. Your config at `~/.config/multmux.conf` is left untouched since the installer only writes it if it doesn't already exist.

### `add` / `remove`

`add` creates a new inner session and switches to it immediately.

`remove` kills the current inner session and switches to the previous one. If it's the last session, a fresh replacement is created automatically (the main pane is never left empty).

### `rename`

Renames the current inner session to the given name. Rejects empty names, names already in use, and names containing `:` or `.`, since tmux reserves those characters for `session:window.pane` targets and a session with either in its name can't be addressed reliably afterwards.

Once a session has been renamed this way, it stops following its working directory (see Session naming below) until multmux is stopped and started again.

### `reset-layout`

Re-applies the configured `MAIN_PANE_WIDTH` and the `main-vertical` layout to the outer session's main and overflow panes. Use it if manual dragging (or anything else) has thrown the pane proportions off. Focus is left untouched.

## Session naming

Inner sessions are named after their current directory, and automatically renamed whenever you `cd`:

- Your home directory is shown as `~` (a session in your home directory itself is named `~/`, not a bare `~`, since tmux reserves the exact string `~` for its own "marked pane" target syntax).
- Any single path component longer than `SESSION_NAME_COMPONENT_MAX` (default 20) is truncated in its own middle, with an ellipsis (e.g. `a-really-long-directory-name` → `a-really-l…tory-name`).
- If the whole name is still longer than `SESSION_NAME_TOTAL_MAX` (default 60) after that, whole components are dropped from the left and replaced with a single leading ellipsis (e.g. `~/work/clients/acme/backend/services/billing` → `…/backend/services/billing`).
- If two sessions would end up with the same name, the newer one gets `-1`, `-2`, etc. appended (lowest available number, reused when a session is removed).
- `:` and `.` are replaced (tmux reserves them for `session:window.pane` targets); this only applies to automatic renaming, since `rename` rejects them outright instead (see above).

Renaming a session manually with `multmux rename` makes it stop following its directory.

## Configuration

Configuration lives at `~/.config/multmux.conf` (a sourced bash file):

```bash
# The initial directory for each pane or session
START_DIR="${HOME}"

# Main pane width (columns or percentage)
MAIN_PANE_WIDTH="60%"

# Number of overflow panes stacked vertically on the right side
OVERFLOW_PANES=3

# Number of inner sessions at start in the main pane (maximum 99)
INNER_SESSIONS=10

# Inner sessions are automatically named/renamed from their current
# directory (see use_dir_as_name.md). Any single path component longer
# than this is truncated in its own middle, with an ellipsis.
SESSION_NAME_COMPONENT_MAX=20

# If the whole computed name is still longer than this after per-component
# truncation, whole components are dropped from the left and replaced with
# a single leading ellipsis. Must be at least SESSION_NAME_COMPONENT_MAX + 2.
SESSION_NAME_TOTAL_MAX=60

# How often (in days) 'multmux start' checks GitHub in the background, at
# most, for a newer version.
AUTO_UPDATE_CHECK_INTERVAL_DAYS=7

# Whether a newer version found by that check is installed automatically.
# If true (the default), it's installed right away. If false, multmux
# only leaves a one-line notice and you install it yourself with
# 'multmux update'.
AUTO_UPDATE=true

# Base tmux config applied to both outer and inner sessions. This is
# loaded directly at server startup for each socket (see the -f flag in
# 'multmux' itself), so your own ~/.config/tmux/tmux.conf or ~/.tmux.conf
# is never read for multmux's sessions -- multmux is fully self-contained
# and your regular tmux usage is never affected by it.
BASE_CONF=$(cat << 'EOF'
# Use vi-style keys in copy mode
setw -g mode-keys vi

# Advertise 256-color support to apps running inside tmux
set default-terminal "screen-256color"
# Unlike for other terminals, tmux doesn't auto-detect true color support in Alacritty
set -as terminal-overrides ",alacritty*:Tc"

# Let Ctrl-a also act as the prefix (keeps prefix usable across nested
# outer/inner multmux sessions without needing to press it twice)
bind-key -n C-a send-prefix
# Prefix + Ctrl-s toggles synchronized input to all panes in the window
bind C-s set-window-option synchronize-panes
# Prefix + arrow keys selects the pane in that direction (explicit default)
bind-key    Up    select-pane -U
bind-key    Down  select-pane -D
bind-key    Left  select-pane -L
bind-key    Right select-pane -R

# Prefix + s opens an interactive session picker, most recent activity first
bind s choose-tree -Zs -O activity

# Recognize Escape quickly so it isn't confused with escape sequences
# (needed by modal editors, e.g. Neovim/lazy.vim)
set-option -sg escape-time 10
# Report terminal focus in/out events to apps that use them (e.g. editor autoread)
set-option -g focus-events on

# Report modified keys (Ctrl/Shift/Alt combos) to apps that request them
# (used by many modern TUIs, e.g. opencode)
set-option -g extended-keys on
# Use the clearer CSI u wire format for those keys, understood by most
# modern terminal apps and TUI libraries (e.g. opencode, prime-agent)
set-option -g extended-keys-format csi-u

# Enable mouse support: click to select/resize panes, wheel to scroll, etc.
set -g mouse on
# Scroll wheel: scroll pane history, or forward to the app if it wants mouse input
bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'copy-mode -e; send-keys -M'"

# Pick the clipboard command for this platform: pbcopy on macOS, else
# wl-copy under Wayland, else xclip under X11
if-shell "command -v pbcopy" \
    "set -g @yank 'pbcopy'" \
    "if-shell \"command -v wl-copy\" \"set -g @yank 'wl-copy'\" \"set -g @yank 'xclip -selection clipboard -in'\""

# Fix select to copy due to above
# Mouse drag-select copies the selection to the system clipboard
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "#{@yank}"
# Double-click selects a word and copies it to the system clipboard
bind -T copy-mode-vi DoubleClick1Pane select-pane \; send-keys -X select-word \; send-keys -X copy-pipe-and-cancel "#{@yank}"
# Triple-click selects a line and copies it to the system clipboard
bind -T copy-mode-vi TripleClick1Pane select-pane \; send-keys -X select-line \; send-keys -X copy-pipe-and-cancel "#{@yank}"

# Keep more scrollback (helps when using multmux's overflow/monitoring panes)
set -g history-limit 10000
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
set-window-option -g automatic-rename on
set-option -g automatic-rename-format "#{pane_current_path}"
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

The socket names are normally fixed (`multmux-outer` and `multmux-inner`), but they can be overridden with environment variables. This is mainly useful for testing changes without touching the sockets of a real, running multmux session:

```bash
MULTMUX_OUTER_SOCKET=multmux-outer-test MULTMUX_INNER_SOCKET=multmux-inner-test ./multmux
```

If the variables are not set, the defaults are used.
