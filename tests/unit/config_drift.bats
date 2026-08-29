#!/usr/bin/env bats
# Unit tests for the config-drift check (config_var_value,
# report_block_drift, check_tmux_config_drift) and its hidden
# 'multmux _check-config-drift' entry point. These specifically guard the
# two real bugs found and fixed in this project's history:
#   1. Comment-only line differences must never be reported as drift.
#   2. 'multmux update' must run the drift check via the freshly-installed
#      binary (re-exec), never via this process's own stale in-memory copy
#      of report_block_drift, since that logic itself can change between
#      versions (see cmd_update/cmd_check_config_drift).

setup() {
    load '../helpers/common'
    mm_set_fake_home
    mm_source
}

# --- config_var_value ---

@test "config_var_value: extracts a plain variable's value" {
    result="$(config_var_value 'FOO="bar"' FOO)"
    [ "${result}" = "bar" ]
}

@test "config_var_value: extracts a heredoc block's full text" {
    text=$'BLOCK=$(cat << \x27EOF\x27\nhello\nworld\nEOF\n)\n'
    result="$(config_var_value "${text}" BLOCK)"
    [[ "${result}" == *"hello"* ]]
    [[ "${result}" == *"world"* ]]
}

@test "config_var_value: never leaks the evaluated variable into the caller's shell" {
    unset LEAK_PROBE 2>/dev/null || true
    config_var_value 'LEAK_PROBE="leaked"' LEAK_PROBE >/dev/null
    [ -z "${LEAK_PROBE:-}" ]
}

@test "config_var_value: malformed config text fails safely (empty result, no error)" {
    run config_var_value 'this is not valid bash((( ' SOMEVAR
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

# --- report_block_drift ---

@test "report_block_drift: identical blocks produce no warning" {
    default=$'INNER_CONF=$(cat << \x27EOF\x27\nset -g status on\nEOF\n)\n'
    user_file="${BATS_TEST_TMPDIR}/user.conf"
    printf '%s' "${default}" > "${user_file}"
    run report_block_drift "${default}" "${user_file}" INNER_CONF
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "report_block_drift: a real missing config line is reported" {
    default=$'INNER_CONF=$(cat << \x27EOF\x27\nset -g status on\nset -g status-interval 1\nEOF\n)\n'
    user=$'INNER_CONF=$(cat << \x27EOF\x27\nset -g status on\nEOF\n)\n'
    user_file="${BATS_TEST_TMPDIR}/user.conf"
    printf '%s' "${user}" > "${user_file}"
    run report_block_drift "${default}" "${user_file}" INNER_CONF
    [[ "${output}" == *"missing lines"* ]]
    [[ "${output}" == *"set -g status-interval 1"* ]]
}

@test "report_block_drift: a differently-worded comment is NOT reported (regression)" {
    default=$'INNER_CONF=$(cat << \x27EOF\x27\n# comment version A with extra words\nset -g status on\nEOF\n)\n'
    user=$'INNER_CONF=$(cat << \x27EOF\x27\n# comment version B, worded totally differently\nset -g status on\nEOF\n)\n'
    user_file="${BATS_TEST_TMPDIR}/user.conf"
    printf '%s' "${user}" > "${user_file}"
    run report_block_drift "${default}" "${user_file}" INNER_CONF
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "report_block_drift: an indented comment (leading whitespace) is also skipped" {
    default=$'INNER_CONF=$(cat << \x27EOF\x27\n    # indented comment A\nset -g status on\nEOF\n)\n'
    user=$'INNER_CONF=$(cat << \x27EOF\x27\n    # indented comment B\nset -g status on\nEOF\n)\n'
    user_file="${BATS_TEST_TMPDIR}/user.conf"
    printf '%s' "${user}" > "${user_file}"
    run report_block_drift "${default}" "${user_file}" INNER_CONF
    [ -z "${output}" ]
}

@test "report_block_drift: a genuinely missing real line is still caught even with unrelated comment drift present" {
    default=$'INNER_CONF=$(cat << \x27EOF\x27\n# comment A\nset -g status on\nset -g new-real-option 1\nEOF\n)\n'
    user=$'INNER_CONF=$(cat << \x27EOF\x27\n# comment B (worded differently)\nset -g status on\nEOF\n)\n'
    user_file="${BATS_TEST_TMPDIR}/user.conf"
    printf '%s' "${user}" > "${user_file}"
    run report_block_drift "${default}" "${user_file}" INNER_CONF
    [[ "${output}" == *"set -g new-real-option 1"* ]]
    [[ "${output}" != *"comment"* ]]
}

@test "report_block_drift: blank lines are never reported as missing" {
    default=$'INNER_CONF=$(cat << \x27EOF\x27\nset -g status on\n\nset -g status off\nEOF\n)\n'
    user=$'INNER_CONF=$(cat << \x27EOF\x27\nset -g status on\nset -g status off\nEOF\n)\n'
    user_file="${BATS_TEST_TMPDIR}/user.conf"
    printf '%s' "${user}" > "${user_file}"
    run report_block_drift "${default}" "${user_file}" INNER_CONF
    [ -z "${output}" ]
}

# --- check_tmux_config_drift ---

@test "check_tmux_config_drift: does nothing if CONF_FILE doesn't exist" {
    run check_tmux_config_drift "${DEFAULT_CONFIG}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "check_tmux_config_drift: the real bundled default against itself reports nothing" {
    mm_install_default_config
    run check_tmux_config_drift "${DEFAULT_CONFIG}"
    [ -z "${output}" ]
}

@test "check_tmux_config_drift: reports only the block that actually drifted" {
    mm_install_default_config
    # Remove the INNER_CONF status-interval line from the user's file to
    # create real drift in exactly one block.
    sed -i.bak '/set -g status-interval 1/d' "${HOME}/.config/multmux.conf"
    run check_tmux_config_drift "${DEFAULT_CONFIG}"
    [[ "${output}" == *"INNER_CONF is missing"* ]]
    [[ "${output}" != *"BASE_CONF is missing"* ]]
    [[ "${output}" != *"OUTER_CONF is missing"* ]]
}

# --- end-to-end via the real hidden subcommand (regression for bug #2) ---

@test "'multmux _check-config-drift': no warning for the real default config against itself" {
    mm_install_default_config
    run "${MULTMUX_SCRIPT}" _check-config-drift
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "'multmux _check-config-drift': catches real drift end-to-end through the actual subcommand dispatch" {
    mm_install_default_config
    sed -i.bak '/set -g status-interval 1/d' "${HOME}/.config/multmux.conf"
    run "${MULTMUX_SCRIPT}" _check-config-drift
    [[ "${output}" == *"missing lines"* ]]
    [[ "${output}" == *"status-interval"* ]]
}

@test "'multmux _check-config-drift': a comment-only difference produces no warning through the actual subcommand dispatch" {
    # This is the exact real-world scenario that motivated the fix: the
    # user's installed config has the same tmux directives as the bundled
    # default but slightly different comment wording nearby.
    mm_install_default_config
    sed -i.bak 's/hook below/hook/' "${HOME}/.config/multmux.conf"
    run "${MULTMUX_SCRIPT}" _check-config-drift
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "regression: cmd_update re-execs SELF_PATH for the drift check instead of running it in-process" {
    # Structural guard against silently reintroducing the staleness bug:
    # cmd_update must delegate the ENTIRE drift check (data AND logic) to
    # the freshly-installed binary via SELF_PATH, not call
    # check_tmux_config_drift directly using this process's own (possibly
    # stale) copy of that logic.
    body="$(sed -n '/^cmd_update() {/,/^}/p' "${MULTMUX_SCRIPT}")"
    [[ "${body}" == *'"${SELF_PATH}" _check-config-drift'* ]]
    [[ "${body}" != *'check_tmux_config_drift "${new_default_config}"'* ]]
}

@test "defaults/multmux.conf (what fresh installs get) never drifts from the script's embedded DEFAULT_CONFIG" {
    # Regression for the bug found while writing these tests: the
    # status-interval fix was added to DEFAULT_CONFIG inside the multmux
    # script but initially missed defaults/multmux.conf, the file
    # install.sh actually ships to brand-new users.
    bundled_file="${MULTMUX_REPO_ROOT}/defaults/multmux.conf"
    run report_block_drift "${DEFAULT_CONFIG}" "${bundled_file}" BASE_CONF
    [ -z "${output}" ]
    run report_block_drift "${DEFAULT_CONFIG}" "${bundled_file}" OUTER_CONF
    [ -z "${output}" ]
    run report_block_drift "${DEFAULT_CONFIG}" "${bundled_file}" INNER_CONF
    [ -z "${output}" ]
}
