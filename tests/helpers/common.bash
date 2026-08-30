#!/usr/bin/env bash
# Shared bats helpers for multmux tests.
#
# Isolation strategy: every test gets its own throwaway $HOME (so
# CONF_FILE=~/.config/multmux.conf and CACHE_DIR=~/.cache/multmux never
# touch the real, live installation) and, for integration tests that need
# real tmux, its own uniquely-named -L socket pair, so tests never collide
# with each other or with a real running multmux.

MULTMUX_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MULTMUX_SCRIPT="${MULTMUX_REPO_ROOT}/multmux"

# Source multmux for direct function-level testing. Safe to call more than
# once per test (bash re-sourcing just redefines the same functions/vars).
# Must be called AFTER mm_set_fake_home so CONF_FILE/CACHE_DIR resolve
# against the fake $HOME, and the dispatcher guard (BASH_SOURCE vs $0)
# means this never runs the CLI/dies on argv.
mm_source() {
    # shellcheck disable=SC1090
    source "${MULTMUX_SCRIPT}"
}

# Create a fresh throwaway $HOME for this test and point HOME at it, so
# every multmux path derived from $HOME (CONF_FILE, CACHE_DIR, the
# default START_DIR, ~/.local/bin) is fully isolated per test.
mm_set_fake_home() {
    MM_FAKE_HOME="$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/mm-home.XXXXXX")"
    # Canonicalize immediately: on macOS $TMPDIR lives under a /var ->
    # /private/var symlink, so tmux's #{pane_current_path} (which reports
    # the kernel's resolved cwd) would otherwise never string-match a
    # $HOME-derived path computed from the unresolved /var/... form.
    MM_FAKE_HOME="$(cd "${MM_FAKE_HOME}" && pwd -P)"
    export HOME="${MM_FAKE_HOME}"
    mkdir -p "${HOME}/.config" "${HOME}/.cache" "${HOME}/.local/bin"
}

# Install the repo's real defaults/multmux.conf into the fake $HOME,
# exactly like a fresh 'install.sh' run would. Most tests want this: it's
# the actual config shape multmux expects to find at CONF_FILE.
mm_install_default_config() {
    cp "${MULTMUX_REPO_ROOT}/defaults/multmux.conf" "${HOME}/.config/multmux.conf"
}

# Pick a unique, collision-free pair of tmux socket names for this test
# and export them as the MULTMUX_*_SOCKET overrides multmux already
# supports, so integration tests never touch a real running multmux
# (default sockets multmux-outer/multmux-inner) or each other.
mm_set_fake_sockets() {
    local suffix="mmtest-${BATS_TEST_NUMBER:-0}-$$-${RANDOM}"
    export MULTMUX_OUTER_SOCKET="${suffix}-outer"
    export MULTMUX_INNER_SOCKET="${suffix}-inner"
}

# Kill any tmux servers left on this test's sockets. Safe to call even if
# nothing is running. Call from teardown for every integration test.
mm_kill_fake_sockets() {
    [[ -n "${MULTMUX_OUTER_SOCKET:-}" ]] && tmux -L "${MULTMUX_OUTER_SOCKET}" kill-server &>/dev/null || true
    [[ -n "${MULTMUX_INNER_SOCKET:-}" ]] && tmux -L "${MULTMUX_INNER_SOCKET}" kill-server &>/dev/null || true
}

# Full per-test setup for integration tests that actually run multmux as
# a subprocess (not just sourcing its functions): fake $HOME + config +
# fake sockets + guarantee we're not "inside tmux" ourselves (multmux
# refuses to start from inside a tmux session), all in one call.
mm_full_isolation_setup() {
    mm_set_fake_home
    mm_install_default_config
    mm_set_fake_sockets
    unset TMUX
}

# Run multmux as a real subprocess (not sourced), inheriting whatever
# fake HOME/sockets/env the test has already set up. Captures stdout+
# stderr together in $output and the exit code in $status, bats-style
# (works even without bats-support/bats-assert installed).
mm_run() {
    local ec
    output="$("${MULTMUX_SCRIPT}" "$@" 2>&1)"
    ec=$?
    status="${ec}"
    return 0
}

# A directory that looks like a plausible project checkout, for tests
# that need a real, existing path to cd/name a session after.
mm_make_dir() {
    local d="$1"
    mkdir -p "${d}"
    (cd "${d}" && pwd -P)
}

# Build a small, hermetic bin directory containing symlinks to just enough
# real tools (bash, env, and basic coreutils) for scripts to keep working,
# plus caller-supplied fake tools, then point PATH at ONLY that directory.
# Used to genuinely hide a real tool (e.g. simulate "no curl installed")
# rather than just shadowing it, which a PATH-prepend can't guarantee on a
# machine where the real tool exists elsewhere on PATH.
#
# Usage: mm_hermetic_path_without curl   (hide curl entirely, keep wget)
#        mm_hermetic_path_without curl wget   (hide both)
mm_hermetic_path_without() {
    local -a hide=("$@")
    local stubdir="${BATS_TEST_TMPDIR}/hermetic-bin"
    mkdir -p "${stubdir}"
    local tool real skip
    for tool in bash env sh cat echo mktemp sed grep rm mkdir chmod \
        dirname basename tail head wc printf ls sort tr cut mv cp \
        awk date sleep tmux; do
        skip=false
        for real in "${hide[@]}"; do
            [[ "${tool}" == "${real}" ]] && skip=true
        done
        [[ "${skip}" == true ]] && continue
        real="$(command -v "${tool}" 2>/dev/null)" || continue
        ln -sf "${real}" "${stubdir}/${tool}"
    done
    export PATH="${stubdir}"
    hash -r
}

# Pre-seed CACHE_DIR/last_update_check to "just now" so cmd_start's
# background update check short-circuits immediately instead of spawning
# a real (even if disowned) network attempt during a test.
mm_skip_update_check() {
    mkdir -p "${HOME}/.cache/multmux"
    date +%s > "${HOME}/.cache/multmux/last_update_check"
}

# Poll $1 (a command string, via eval) every 0.2s until it succeeds or
# $2 seconds (default 10) pass. Fails the test (via bats' automatic
# nonzero-exit failure) if the timeout is reached.
mm_wait_for() {
    local cond="$1" timeout="${2:-10}" waited=0
    while ! eval "${cond}"; do
        sleep 0.2
        waited=$((waited + 1))
        if ((waited > timeout * 5)); then
            echo "timed out waiting for: ${cond}" >&2
            return 1
        fi
    done
    return 0
}

# Full 'multmux start --no-attach' against fake sockets/home, then wait
# until all inner sessions actually exist before returning (new-session
# calls inside cmd_start are synchronous, but this still gives a little
# slack for the nested nested-attach send-keys to land).
mm_start() {
    mm_skip_update_check
    "${MULTMUX_SCRIPT}" start --no-attach
    mm_wait_for "tmux -L '${MULTMUX_INNER_SOCKET}' list-sessions &>/dev/null" 10
}

# Start a local, throwaway HTTP file server exposing a scratch directory
# that looks like the multmux repo root (multmux, install.sh,
# defaults/multmux.conf), and point MULTMUX_REPO_URL at it. This lets the
# whole self-update pipeline (fetch_latest_version, perform_update,
# install.sh, cmd_update's drift check) be tested for real, offline,
# without touching actual GitHub. Caller must eventually call
# mm_stop_fake_repo_server. Sets MM_FAKE_REPO_DIR and MM_FAKE_REPO_PID.
mm_start_fake_repo_server() {
    MM_FAKE_REPO_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/mm-repo.XXXXXX")"
    mkdir -p "${MM_FAKE_REPO_DIR}/defaults" "${MM_FAKE_REPO_DIR}/completions"
    cp "${MULTMUX_REPO_ROOT}/multmux" "${MM_FAKE_REPO_DIR}/multmux"
    cp "${MULTMUX_REPO_ROOT}/install.sh" "${MM_FAKE_REPO_DIR}/install.sh"
    cp "${MULTMUX_REPO_ROOT}/defaults/multmux.conf" "${MM_FAKE_REPO_DIR}/defaults/multmux.conf"
    cp "${MULTMUX_REPO_ROOT}/completions/multmux.bash" "${MM_FAKE_REPO_DIR}/completions/multmux.bash"
    cp "${MULTMUX_REPO_ROOT}/completions/multmux.zsh" "${MM_FAKE_REPO_DIR}/completions/multmux.zsh"
    chmod +x "${MM_FAKE_REPO_DIR}/multmux" "${MM_FAKE_REPO_DIR}/install.sh"

    local port=0 attempt
    for attempt in $(seq 1 20); do
        port=$((20000 + RANDOM % 20000))
        if ! lsof -i ":${port}" &>/dev/null; then
            break
        fi
    done

    (
        cd "${MM_FAKE_REPO_DIR}" && exec python3 -m http.server "${port}" --bind 127.0.0.1
    ) &>"${MM_FAKE_REPO_DIR}/server.log" &
    MM_FAKE_REPO_PID=$!
    export MULTMUX_REPO_URL="http://127.0.0.1:${port}"

    mm_wait_for "curl -fsS -o /dev/null '${MULTMUX_REPO_URL}/multmux'" 10
}

# Replace VERSION="x.y.z" in the fake repo's served multmux script (and
# report it as the installed version so install.sh's own version print
# stays consistent), simulating "a newer release is available".
mm_fake_repo_set_version() {
    local new_version="$1"
    sed -i.bak -E "s/^VERSION=\"[0-9]+\.[0-9]+\.[0-9]+\"/VERSION=\"${new_version}\"/" \
        "${MM_FAKE_REPO_DIR}/multmux"
}

# Append arbitrary extra tmux config text to the fake repo's INNER_CONF
# block (used to simulate "the newer version adds a real config line",
# for drift-check end-to-end tests). Must be called before the server is
# read for that content (the file is served straight off disk, so this
# just has to happen before the relevant HTTP request, not before the
# server starts).
mm_fake_repo_add_inner_conf_line() {
    local extra_line="$1"
    sed -i.bak "s/^set-window-option -g automatic-rename on\$/${extra_line}\nset-window-option -g automatic-rename on/" \
        "${MM_FAKE_REPO_DIR}/multmux" "${MM_FAKE_REPO_DIR}/defaults/multmux.conf"
}

mm_stop_fake_repo_server() {
    [[ -n "${MM_FAKE_REPO_PID:-}" ]] && kill "${MM_FAKE_REPO_PID}" &>/dev/null || true
    wait "${MM_FAKE_REPO_PID:-}" 2>/dev/null || true
}

# Install a copy of the multmux script under test into the fake $HOME's
# ~/.local/bin, matching a real installation, and return that path. Tests
# of 'multmux update' must invoke THIS path (not $MULTMUX_SCRIPT directly):
# SELF_PATH is resolved from how the running script was invoked
# (BASH_SOURCE[0]), and cmd_update's whole "re-exec the freshly-installed
# binary" design assumes SELF_PATH is the same file install.sh just
# overwrote, which is only true when multmux is run from its installed
# location, exactly like a real user's PATH-resolved 'multmux' command.
mm_install_self() {
    mkdir -p "${HOME}/.local/bin"
    cp "${MULTMUX_SCRIPT}" "${HOME}/.local/bin/multmux"
    chmod +x "${HOME}/.local/bin/multmux"
    printf '%s' "${HOME}/.local/bin/multmux"
}
