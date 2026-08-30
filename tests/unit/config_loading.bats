#!/usr/bin/env bats
# Unit tests for config parsing and validation. Runtime commands never mutate
# the user's configuration.

setup() {
    load '../helpers/common'
    mm_set_fake_home
    mm_source
}

# --- parse_config_blocks ---

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

@test "load_config: rejects a missing required variable without modifying the file" {
    mm_install_default_config
    sed -i.bak '/^OVERFLOW_PANES=/d' "${HOME}/.config/multmux.conf"
    local before
    before="$(cat "${HOME}/.config/multmux.conf")"

    run load_config

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"missing required variable"* ]]
    [ "$(cat "${HOME}/.config/multmux.conf")" = "${before}" ]
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
