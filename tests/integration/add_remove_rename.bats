#!/usr/bin/env bats
# Integration tests for cmd_add / cmd_remove / cmd_rename / cmd_list,
# against real (isolated) tmux servers.

setup() {
    load '../helpers/common'
    mm_full_isolation_setup
}

teardown() {
    mm_kill_fake_sockets
}

@test "add: fails clearly when multmux is not running" {
    run "${MULTMUX_SCRIPT}" add
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not running"* ]]
}

@test "add: creates a new session and switches the inner client to it" {
    mm_start
    before="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_name}' | wc -l | tr -d ' ')"
    run "${MULTMUX_SCRIPT}" add
    [ "${status}" -eq 0 ]
    after="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_name}' | wc -l | tr -d ' ')"
    [ "$((after))" -eq "$((before + 1))" ]
}

@test "add: the new session's name collides on the same START_DIR-derived base, gets the next free suffix" {
    mm_start
    run "${MULTMUX_SCRIPT}" add
    # START_DIR default is ~, base name "~/" already taken 10x (~/ .. ~/-9),
    # so the new one must be ~/-10, the next free integer.
    run tmux -L "${MULTMUX_INNER_SOCKET}" has-session -t "~/-10"
    [ "${status}" -eq 0 ]
}

@test "add: with an explicit path argument creates a session rooted and named there" {
    mm_start
    dir="$(mm_make_dir "${HOME}/myproject")"
    run "${MULTMUX_SCRIPT}" add "${dir}"
    [ "${status}" -eq 0 ]
    run tmux -L "${MULTMUX_INNER_SOCKET}" has-session -t "~/myproject"
    [ "${status}" -eq 0 ]
    run tmux -L "${MULTMUX_INNER_SOCKET}" display-message -p -t "~/myproject" '#{pane_current_path}'
    [ "${output}" = "${dir}" ]
}

@test "add: a bare '.' resolves to the invoking shell's current directory" {
    mm_start
    dir="$(mm_make_dir "${HOME}/dotproject")"
    run bash -c "cd '${dir}' && '${MULTMUX_SCRIPT}' add ."
    [ "${status}" -eq 0 ]
    run tmux -L "${MULTMUX_INNER_SOCKET}" has-session -t "~/dotproject"
    [ "${status}" -eq 0 ]
}

@test "add: dies clearly when the given path does not exist" {
    mm_start
    run "${MULTMUX_SCRIPT}" add "${HOME}/no/such/dir"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Directory not found"* ]]
}

@test "add: rejects more than one argument" {
    mm_start
    run "${MULTMUX_SCRIPT}" add foo bar
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Usage"* ]]
}

@test "remove: fails clearly when multmux is not running" {
    run "${MULTMUX_SCRIPT}" remove
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not running"* ]]
}

@test "remove: rejects unexpected arguments" {
    mm_start
    run "${MULTMUX_SCRIPT}" remove extra-arg
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown option"* ]]
}

@test "remove: removes the current session and switches to another one, session count stays >= 1" {
    mm_start
    before="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_name}' | wc -l | tr -d ' ')"
    run "${MULTMUX_SCRIPT}" remove
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Removed"* ]]
    after="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_name}' | wc -l | tr -d ' ')"
    [ "$((after))" -eq "$((before - 1))" ]
}

@test "remove: removing the very last session creates a fresh replacement instead of leaving zero" {
    mm_start
    # Kill down to exactly one inner session first (simulate having
    # already removed the rest), keeping the attached one.
    current="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-clients -F '#{session_name}')"
    while true; do
        n="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_name}' | wc -l | tr -d ' ')"
        [ "${n}" -le 1 ] && break
        victim="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_name}' | grep -vx "${current}" | head -1)"
        tmux -L "${MULTMUX_INNER_SOCKET}" kill-session -t "${victim}"
    done
    run "${MULTMUX_SCRIPT}" remove
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Last session. Creating a replacement"* ]]
    run bash -c "tmux -L '${MULTMUX_INNER_SOCKET}' list-sessions | wc -l | tr -d ' '"
    [ "${output}" -eq 1 ]
}

@test "rename: fails clearly when multmux is not running" {
    run "${MULTMUX_SCRIPT}" rename foo
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not running"* ]]
}

@test "rename: requires exactly one argument" {
    mm_start
    run "${MULTMUX_SCRIPT}" rename
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Usage"* ]]
}

@test "rename: rejects a name containing ':' or '.'" {
    mm_start
    run "${MULTMUX_SCRIPT}" rename "bad:name"
    [ "${status}" -ne 0 ]
    run "${MULTMUX_SCRIPT}" rename "bad.name"
    [ "${status}" -ne 0 ]
}

@test "rename: renames the current session and marks it sticky (@multmux_renamed)" {
    mm_start
    run "${MULTMUX_SCRIPT}" rename "my-custom-name"
    [ "${status}" -eq 0 ]
    run tmux -L "${MULTMUX_INNER_SOCKET}" has-session -t "my-custom-name"
    [ "${status}" -eq 0 ]
    sticky="$(tmux -L "${MULTMUX_INNER_SOCKET}" show-options -v -t "my-custom-name" '@multmux_renamed')"
    [ "${sticky}" = "1" ]
}

@test "rename: refuses to collide with an existing session name" {
    mm_start
    run "${MULTMUX_SCRIPT}" rename "~/-1"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"already exists"* ]]
}

@test "rename: a name with regex metacharacters overlapping another session's literal name is not falsely rejected" {
    mm_start
    # "~/-[12]" is a valid name (only ':' and '.' are rejected) that, if
    # matched as a regex instead of a literal string, would look like it
    # collides with the existing "~/-1"/"~/-2" sessions from mm_start.
    run "${MULTMUX_SCRIPT}" rename "~/-[12]"
    [ "${status}" -eq 0 ]
    run tmux -L "${MULTMUX_INNER_SOCKET}" has-session -t "~/-[12]"
    [ "${status}" -eq 0 ]
}

@test "rename: renaming to the session's own current name is a harmless no-op" {
    mm_start
    current="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-clients -F '#{session_name}')"
    run "${MULTMUX_SCRIPT}" rename "${current}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"already named"* ]]
}

@test "rename: a manually renamed session is no longer auto-renamed by the CWD hook" {
    mm_start
    "${MULTMUX_SCRIPT}" rename "sticky-name"
    d="$(mm_make_dir "${BATS_TEST_TMPDIR}/somewhere-else")"
    tmux -L "${MULTMUX_INNER_SOCKET}" send-keys -t "sticky-name" "cd ${d}" Enter
    tmux -L "${MULTMUX_INNER_SOCKET}" send-keys -t "sticky-name" "" Enter
    mm_wait_for "tmux -L '${MULTMUX_INNER_SOCKET}' display-message -p -t sticky-name '#{pane_current_path}' | grep -qx '${d}'" 5
    sleep 1
    run tmux -L "${MULTMUX_INNER_SOCKET}" has-session -t "sticky-name"
    [ "${status}" -eq 0 ]
}

@test "list: fails clearly when multmux is not running" {
    run "${MULTMUX_SCRIPT}" list
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not running"* ]]
}

@test "list: shows all sessions with the current one marked active" {
    mm_start
    run "${MULTMUX_SCRIPT}" list
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"* ~/ (active)"* ]]
    [[ "${output}" == *"~/-1"* ]]
}
