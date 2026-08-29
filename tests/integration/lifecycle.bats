#!/usr/bin/env bats
# Integration tests for the core lifecycle commands, against real (but
# fully isolated) tmux servers on throwaway sockets: start, stop, the
# "already running" fast path, orphan cleanup, and the nested-tmux guard.

setup() {
    load '../helpers/common'
    mm_full_isolation_setup
}

teardown() {
    mm_kill_fake_sockets
}

@test "start: creates the outer session and the configured number of inner sessions" {
    mm_start
    run tmux -L "${MULTMUX_OUTER_SOCKET}" list-sessions
    [ "${status}" -eq 0 ]
    run bash -c "tmux -L '${MULTMUX_INNER_SOCKET}' list-sessions | wc -l | tr -d ' '"
    [ "${output}" -eq 10 ]
}

@test "start: the first inner session is named after START_DIR and is attached" {
    mm_start
    run tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_name} #{session_attached}'
    [[ "${output}" == *"~/ 1"* ]]
}

@test "start: numbers collide-by-default inner sessions -1 through -9" {
    mm_start
    for n in 1 2 3 4 5 6 7 8 9; do
        run tmux -L "${MULTMUX_INNER_SOCKET}" has-session -t "~/-${n}"
        [ "${status}" -eq 0 ]
    done
}

@test "start: is idempotent, 'already running' fast path does not recreate sessions" {
    mm_start
    before="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_created}' | sort)"
    run "${MULTMUX_SCRIPT}" start --no-attach
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Already running"* ]]
    after="$(tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions -F '#{session_created}' | sort)"
    [ "${before}" = "${after}" ]
}

@test "start: refuses to run from inside a tmux session (nested)" {
    export TMUX="fake:pretend-nested"
    run "${MULTMUX_SCRIPT}" start --no-attach
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Cannot start from inside a tmux session"* ]]
    run tmux -L "${MULTMUX_OUTER_SOCKET}" list-sessions
    [ "${status}" -ne 0 ]
}

@test "start: rejects an unknown option" {
    run "${MULTMUX_SCRIPT}" start --bogus-flag
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown option"* ]]
}

@test "start: cleans up orphaned inner sessions left by a previous crashed run" {
    # Simulate a crash: inner sessions exist but the outer one never
    # started (or already died), which a real crash between the two
    # 'new-session' calls in cmd_start could leave behind.
    mm_skip_update_check
    tmux -L "${MULTMUX_INNER_SOCKET}" new-session -d -s orphan-leftover
    run tmux -L "${MULTMUX_OUTER_SOCKET}" list-sessions
    [ "${status}" -ne 0 ] # outer genuinely not running yet

    mm_start
    run tmux -L "${MULTMUX_INNER_SOCKET}" has-session -t orphan-leftover
    [ "${status}" -ne 0 ] # the orphan is gone, replaced by a clean start
    run bash -c "tmux -L '${MULTMUX_INNER_SOCKET}' list-sessions | wc -l | tr -d ' '"
    [ "${output}" -eq 10 ]
}

@test "stop: reports 'Not running' and does nothing when nothing is running" {
    run "${MULTMUX_SCRIPT}" stop
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Not running"* ]]
}

@test "stop: declining the confirmation prompt leaves sessions running" {
    mm_start
    run bash -c "printf 'n\n' | '${MULTMUX_SCRIPT}' stop"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Aborted"* ]]
    run tmux -L "${MULTMUX_OUTER_SOCKET}" list-sessions
    [ "${status}" -eq 0 ]
}

@test "stop: any answer other than y/Y aborts (e.g. an empty line)" {
    mm_start
    run bash -c "printf '\n' | '${MULTMUX_SCRIPT}' stop"
    [[ "${output}" == *"Aborted"* ]]
    run tmux -L "${MULTMUX_OUTER_SOCKET}" list-sessions
    [ "${status}" -eq 0 ]
}

@test "stop: closed stdin (EOF) aborts cleanly instead of crashing silently" {
    mm_start
    run bash -c "'${MULTMUX_SCRIPT}' stop < /dev/null"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Aborted"* ]]
    run tmux -L "${MULTMUX_OUTER_SOCKET}" list-sessions
    [ "${status}" -eq 0 ]
}

@test "stop: confirming with 'y' kills both outer and inner servers" {
    mm_start
    run bash -c "printf 'y\n' | '${MULTMUX_SCRIPT}' stop"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Stopped."* ]]
    run tmux -L "${MULTMUX_OUTER_SOCKET}" list-sessions
    [ "${status}" -ne 0 ]
    run tmux -L "${MULTMUX_INNER_SOCKET}" list-sessions
    [ "${status}" -ne 0 ]
}

@test "stop: confirming with uppercase 'Y' also works" {
    mm_start
    run bash -c "printf 'Y\n' | '${MULTMUX_SCRIPT}' stop"
    [[ "${output}" == *"Stopped."* ]]
}

@test "reset-layout: fails clearly when multmux is not running" {
    run "${MULTMUX_SCRIPT}" reset-layout
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not running"* ]]
}

@test "reset-layout: succeeds when running" {
    mm_start
    run "${MULTMUX_SCRIPT}" reset-layout
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Done."* ]]
}

@test "attach: fails clearly when multmux is not running" {
    run "${MULTMUX_SCRIPT}" attach
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not running"* ]]
}

@test "detach: reports 'Not attached' when there is no real client" {
    mm_start
    run "${MULTMUX_SCRIPT}" detach
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Not attached"* ]]
}
