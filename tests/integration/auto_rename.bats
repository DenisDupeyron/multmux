#!/usr/bin/env bats
# Integration tests for the CWD-based auto-rename hook: cmd_auto_rename
# directly, the real tmux window-renamed hook end to end, the
# sticky-after-manual-rename flag, and prompt status-line updates.

setup() {
    load '../helpers/common'
    mm_full_isolation_setup
}

teardown() {
    mm_kill_fake_sockets
}

@test "_auto-rename: does nothing (no error) when inner sessions aren't running" {
    run "${MULTMUX_SCRIPT}" _auto-rename '$0'
    [ "${status}" -eq 0 ]
}

@test "_auto-rename: renames a session to match its current directory" {
    mm_start
    d="$(mm_make_dir "${HOME}/proj")"
    sid="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_id}' | head -1)"
    sname="$(tmux -L "${MULTMUX_INNER_SOCKET}" display-message -p -t "${sid}" '#{session_name}')"
    tmux -L "${MULTMUX_INNER_SOCKET}" send-keys -t "${sname}" "cd ${d}" Enter
    mm_wait_for "tmux -L '${MULTMUX_INNER_SOCKET}' display-message -p -t '${sid}' '#{pane_current_path}' | grep -qx '${d}'" 5

    run "${MULTMUX_SCRIPT}" _auto-rename "${sid}"
    [ "${status}" -eq 0 ]
    run tmux -L "${MULTMUX_INNER_SOCKET}" display-message -p -t "${sid}" '#{session_name}'
    [ "${output}" = "~/proj" ]
}

@test "_auto-rename: leaves a manually renamed (sticky) session alone" {
    mm_start
    sid="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_id}' | head -1)"
    tmux -L "${MULTMUX_INNER_SOCKET}" rename-session -t "${sid}" "pinned"
    tmux -L "${MULTMUX_INNER_SOCKET}" set-option -t "pinned" @multmux_renamed 1
    d="$(mm_make_dir "${BATS_TEST_TMPDIR}/elsewhere")"
    tmux -L "${MULTMUX_INNER_SOCKET}" send-keys -t "pinned" "cd ${d}" Enter
    mm_wait_for "tmux -L '${MULTMUX_INNER_SOCKET}' display-message -p -t '${sid}' '#{pane_current_path}' | grep -q elsewhere" 5

    run "${MULTMUX_SCRIPT}" _auto-rename "${sid}"
    run tmux -L "${MULTMUX_INNER_SOCKET}" display-message -p -t "${sid}" '#{session_name}'
    [ "${output}" = "pinned" ]
}

@test "_auto-rename: colliding with a different existing session gets a numeric suffix" {
    mm_start
    # "~/" itself already exists (the attached, START_DIR session from the
    # batch start). Cd a DIFFERENT session (~/-1) to $HOME too, so its
    # computed base name ("~/") collides with that already-taken name and
    # must fall back to the next free numeric suffix.
    sid="$(tmux -L "${MULTMUX_INNER_SOCKET}" display-message -p -t '~/-1' '#{session_id}')"
    tmux -L "${MULTMUX_INNER_SOCKET}" send-keys -t "${sid}" "cd \${HOME}" Enter
    mm_wait_for "tmux -L '${MULTMUX_INNER_SOCKET}' display-message -p -t '${sid}' '#{pane_current_path}' | grep -qx '${HOME}'" 5

    run "${MULTMUX_SCRIPT}" _auto-rename "${sid}"
    run tmux -L "${MULTMUX_INNER_SOCKET}" display-message -p -t "${sid}" '#{session_name}'
    [[ "${output}" == "~/-"* ]]
    [ "${output}" != "~/" ] # ~/ itself is still the other (attached) session
}

@test "end-to-end: a real 'cd' in the pane actually triggers the tmux hook and renames the session" {
    mm_start
    d="$(mm_make_dir "${HOME}/realcd")"
    sid="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-clients -F '#{session_id}')"
    tmux -L "${MULTMUX_INNER_SOCKET}" send-keys -t "${sid}" "cd ${d}" Enter
    # No manual '_auto-rename' call here: this only passes if tmux's own
    # automatic-rename + window-renamed hook (wired up by write_temp_configs)
    # actually fires on its own, exactly like real interactive use.
    mm_wait_for "tmux -L '${MULTMUX_INNER_SOCKET}' display-message -p -t '${sid}' '#{session_name}' | grep -qx '~/realcd'" 10
}

@test "end-to-end: the auto-rename hook runs from an executable path containing spaces" {
    local install_dir="${BATS_TEST_TMPDIR}/multmux install"
    local installed="${install_dir}/multmux"
    mkdir -p "${install_dir}"
    cp "${MULTMUX_SCRIPT}" "${installed}"
    chmod +x "${installed}"

    mm_skip_update_check
    "${installed}" start --no-attach
    d="$(mm_make_dir "${HOME}/space-path")"
    sid="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-clients -F '#{session_id}')"
    tmux -L "${MULTMUX_INNER_SOCKET}" send-keys -t "${sid}" "cd ${d}" Enter

    mm_wait_for "tmux -L '${MULTMUX_INNER_SOCKET}' display-message -p -t '${sid}' '#{session_name}' | grep -qx '~/space-path'" 10
}

@test "the inner tmux config sets status-interval to 1 (keeps the status line from lagging)" {
    mm_start
    run tmux -L "${MULTMUX_INNER_SOCKET}" show-options -g status-interval
    [ "${output}" = "status-interval 1" ]
}
