#!/usr/bin/env bats
# Unit tests for shell-completion support: cmd_commands (the single
# source of truth completion scripts consume) and static validity of the
# checked-in completion scripts themselves. No tmux required.

setup() {
    load '../helpers/common'
    mm_set_fake_home
    mm_source
}

# --- cmd_commands ---

@test "cmd_commands: lists every public subcommand" {
    run cmd_commands
    [ "${status}" -eq 0 ]
    for cmd in start stop attach detach add remove rename status reset-layout update help version; do
        [[ "${output}" == *"${cmd}"* ]]
    done
}

@test "cmd_commands: excludes internal-only commands" {
    run cmd_commands
    [[ "${output}" != *"_auto-rename"* ]]
    [[ "${output}" != *"_check-config-drift"* ]]
    [[ "${output}" != *"_commands"* ]]
}

@test "multmux _commands: reachable through the real CLI dispatch" {
    run "${MULTMUX_SCRIPT}" _commands
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"start"* ]]
}

# --- Static script validity ---

@test "completions/multmux.bash: valid bash syntax" {
    run bash -n "${MULTMUX_REPO_ROOT}/completions/multmux.bash"
    [ "${status}" -eq 0 ]
}

@test "completions/multmux.zsh: valid zsh syntax" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -n "${MULTMUX_REPO_ROOT}/completions/multmux.zsh"
    [ "${status}" -eq 0 ]
}

# --- Bash completion behavior (real bash, no tmux) ---

@test "completions/multmux.bash: top-level completion lists every command" {
    run bash -c "
        PATH=${MULTMUX_REPO_ROOT}:\${PATH}
        source '${MULTMUX_REPO_ROOT}/completions/multmux.bash'
        COMP_WORDS=(multmux '')
        COMP_CWORD=1
        _multmux
        printf '%s\n' \"\${COMPREPLY[@]}\"
    "
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"start"* ]]
    [[ "${output}" == *"status"* ]]
}

@test "completions/multmux.bash: completes --no-attach after 'start'" {
    run bash -c "
        PATH=${MULTMUX_REPO_ROOT}:\${PATH}
        source '${MULTMUX_REPO_ROOT}/completions/multmux.bash'
        COMP_WORDS=(multmux start '')
        COMP_CWORD=2
        _multmux
        printf '%s\n' \"\${COMPREPLY[@]}\"
    "
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--no-attach"* ]]
}

@test "completions/multmux.bash: completes directories after 'add'" {
    mm_make_dir "${BATS_TEST_TMPDIR}/completion-target" >/dev/null
    run bash -c "
        PATH=${MULTMUX_REPO_ROOT}:\${PATH}
        source '${MULTMUX_REPO_ROOT}/completions/multmux.bash'
        cd '${BATS_TEST_TMPDIR}'
        COMP_WORDS=(multmux add '')
        COMP_CWORD=2
        _multmux
        printf '%s\n' \"\${COMPREPLY[@]}\"
    "
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"completion-target"* ]]
}

@test "completions/multmux.zsh: loads and defines _multmux without error" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -c "
        source '${MULTMUX_REPO_ROOT}/completions/multmux.zsh'
        declare -f _multmux >/dev/null 2>&1 && echo defined
    "
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"defined"* ]]
}
