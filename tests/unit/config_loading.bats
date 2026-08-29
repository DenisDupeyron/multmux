#!/usr/bin/env bats
# Unit tests for config parsing/loading/healing: parse_config_blocks,
# reconcile_missing_vars, load_config. Uses a real (but throwaway)
# $HOME/.config/multmux.conf on disk since these functions read/write
# CONF_FILE directly; no tmux or network involved.

setup() {
    load '../helpers/common'
    mm_set_fake_home
    mm_source
}

# --- parse_config_blocks ---

@test "parse_config_blocks: a simple single-line assignment" {
    parse_config_blocks 'FOO="bar"'
    [ "${#CONFIG_BLOCK_NAMES[@]}" -eq 1 ]
    [ "${CONFIG_BLOCK_NAMES[0]}" = "FOO" ]
    [ "${CONFIG_BLOCK_TEXT[FOO]}" = $'FOO="bar"\n' ]
}

@test "parse_config_blocks: a heredoc-style block captures everything through the closing paren" {
    content=$'BASE_CONF=$(cat << \x27EOF\x27\nline one\nline two\nEOF\n)\n'
    parse_config_blocks "${content}"
    [ "${#CONFIG_BLOCK_NAMES[@]}" -eq 1 ]
    [ "${CONFIG_BLOCK_NAMES[0]}" = "BASE_CONF" ]
    [[ "${CONFIG_BLOCK_TEXT[BASE_CONF]}" == *"line one"* ]]
    [[ "${CONFIG_BLOCK_TEXT[BASE_CONF]}" == *"line two"* ]]
}

@test "parse_config_blocks: comments/blank lines before a variable are attached to that variable's block" {
    content=$'# a comment\n\nFOO="bar"\n'
    parse_config_blocks "${content}"
    [ "${CONFIG_BLOCK_TEXT[FOO]}" = "${content}" ]
}

@test "parse_config_blocks: multiple variables are all captured in declaration order" {
    content=$'A="1"\nB="2"\nC="3"\n'
    parse_config_blocks "${content}"
    [ "${CONFIG_BLOCK_NAMES[0]}" = "A" ]
    [ "${CONFIG_BLOCK_NAMES[1]}" = "B" ]
    [ "${CONFIG_BLOCK_NAMES[2]}" = "C" ]
}

@test "parse_config_blocks: records the 1-based end line of each block" {
    content=$'A="1"\nB="2"\n'
    parse_config_blocks "${content}"
    [ "${CONFIG_BLOCK_END_LINE[A]}" -eq 1 ]
    [ "${CONFIG_BLOCK_END_LINE[B]}" -eq 2 ]
}

# --- reconcile_missing_vars ---

@test "reconcile_missing_vars: returns 1 immediately when nothing is missing" {
    mm_install_default_config
    run reconcile_missing_vars
    [ "${status}" -eq 1 ]
}

@test "reconcile_missing_vars: returns 1 when a missing name isn't in DEFAULT_CONFIG either (unhealable)" {
    mm_install_default_config
    run reconcile_missing_vars "NOT_A_REAL_VARIABLE"
    [ "${status}" -eq 1 ]
}

@test "reconcile_missing_vars: splices a genuinely missing (but known-default) variable into the file and reports it" {
    # Build a user config that's the real default minus the AUTO_UPDATE line.
    mm_install_default_config
    grep -v '^AUTO_UPDATE=' "${HOME}/.config/multmux.conf" > "${HOME}/.config/multmux.conf.tmp"
    mv "${HOME}/.config/multmux.conf.tmp" "${HOME}/.config/multmux.conf"
    run bash -c 'source "'"${MULTMUX_SCRIPT}"'"; reconcile_missing_vars "AUTO_UPDATE"'
    [ "${status}" -eq 0 ]
    grep -q '^AUTO_UPDATE=' "${HOME}/.config/multmux.conf"
}

@test "reconcile_missing_vars: healed file still sources cleanly afterward" {
    mm_install_default_config
    grep -v '^AUTO_UPDATE=' "${HOME}/.config/multmux.conf" > "${HOME}/.config/multmux.conf.tmp"
    mv "${HOME}/.config/multmux.conf.tmp" "${HOME}/.config/multmux.conf"
    bash -c 'source "'"${MULTMUX_SCRIPT}"'"; reconcile_missing_vars "AUTO_UPDATE"' >/dev/null
    run bash -c 'source "'"${HOME}/.config/multmux.conf"'"; echo "${AUTO_UPDATE}"'
    [ "${status}" -eq 0 ]
    [ "${output}" = "true" ]
}

# --- load_config ---

@test "load_config: dies clearly if CONF_FILE does not exist at all" {
    run load_config
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Config not found"* ]]
}

@test "load_config: succeeds with the real default config, no vars missing" {
    mm_install_default_config
    run load_config
    [ "${status}" -eq 0 ]
}

@test "load_config: auto-heals a missing-but-healable REQUIRED variable and still succeeds" {
    # OVERFLOW_PANES is one of load_config's required_vars, so removing it
    # (while it's still present in DEFAULT_CONFIG) exercises the real
    # auto-heal path, unlike AUTO_UPDATE which isn't required at all.
    mm_install_default_config
    sed -i.bak '/^OVERFLOW_PANES=/d' "${HOME}/.config/multmux.conf"
    run load_config
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"missing settings"* ]]
    grep -q '^OVERFLOW_PANES=' "${HOME}/.config/multmux.conf"
}

@test "load_config: dies if a required variable is missing from the file AND from DEFAULT_CONFIG (truly unhealable)" {
    # Every required_vars entry is, by construction, always present in the
    # real DEFAULT_CONFIG, so genuinely hitting the "unhealable" die path
    # needs DEFAULT_CONFIG itself to also be missing that variable, e.g. a
    # future maintenance bug where required_vars grows but the bundled
    # default doesn't. Simulated here directly to prove that failure path
    # still works correctly if it's ever reached.
    mm_install_default_config
    sed -i.bak '/^OVERFLOW_PANES=/d' "${HOME}/.config/multmux.conf"
    DEFAULT_CONFIG="${DEFAULT_CONFIG//OVERFLOW_PANES/OVERFLOW_PANES_RENAMED}"
    run load_config
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"missing required variable"* ]]
}

@test "load_config: dies if SESSION_NAME_TOTAL_MAX is less than SESSION_NAME_COMPONENT_MAX + 2" {
    mm_install_default_config
    printf '\nSESSION_NAME_COMPONENT_MAX=20\nSESSION_NAME_TOTAL_MAX=21\n' >> "${HOME}/.config/multmux.conf"
    run load_config
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"must be at least"* ]]
}

@test "load_config: accepts SESSION_NAME_TOTAL_MAX exactly at the minimum allowed (COMPONENT_MAX + 2)" {
    mm_install_default_config
    printf '\nSESSION_NAME_COMPONENT_MAX=20\nSESSION_NAME_TOTAL_MAX=22\n' >> "${HOME}/.config/multmux.conf"
    run load_config
    [ "${status}" -eq 0 ]
}
