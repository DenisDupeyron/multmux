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

# --- load_config: layered system + user files ---

@test "load_config: neither file exists, error lists both searched paths" {
    run load_config
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Config not found"* ]]
    [[ "${output}" == *"${MULTMUX_SYSTEM_CONF}"* ]]
    [[ "${output}" == *"${CONF_FILE}"* ]]
}

@test "load_config: system file only, values come from it" {
    mm_write_system_config "$(cat "${MULTMUX_REPO_ROOT}/defaults/multmux.conf")"
    printf '\nINNER_SESSIONS=4\n' >>"${MULTMUX_SYSTEM_CONF}"
    [ ! -f "${CONF_FILE}" ]
    load_config
    [ "${INNER_SESSIONS}" = "4" ]
    [ "${OVERFLOW_PANES}" = "3" ]
}

@test "load_config: user file only behaves as before" {
    mm_install_default_config
    [ ! -f "${MULTMUX_SYSTEM_CONF}" ]
    load_config
    [ "${INNER_SESSIONS}" = "10" ]
}

@test "load_config: user value overrides system, system-only variable stays visible" {
    mm_write_system_config "$(cat "${MULTMUX_REPO_ROOT}/defaults/multmux.conf")"
    printf '\nINNER_SESSIONS=4\nOVERFLOW_PANES=5\n' >>"${MULTMUX_SYSTEM_CONF}"
    printf 'INNER_SESSIONS=7\n' >"${CONF_FILE}"
    load_config
    [ "${INNER_SESSIONS}" = "7" ]
    [ "${OVERFLOW_PANES}" = "5" ]
}

@test "load_config: user overriding BASE_CONF replaces the system value entirely" {
    mm_write_system_config "$(cat "${MULTMUX_REPO_ROOT}/defaults/multmux.conf")"
    printf 'BASE_CONF="set -g mouse off"\n' >"${CONF_FILE}"
    load_config
    [ "${BASE_CONF}" = "set -g mouse off" ]
}

@test "load_config: required variable missing in user file but present in system file succeeds" {
    mm_write_system_config "$(cat "${MULTMUX_REPO_ROOT}/defaults/multmux.conf")"
    printf 'MAIN_PANE_WIDTH="50%%"\n' >"${CONF_FILE}"
    load_config
    [ "${MAIN_PANE_WIDTH}" = "50%" ]
    [ -n "${BASE_CONF}" ]
}

@test "load_config: required variable missing from both files fails and names it" {
    mm_write_system_config "$(grep -v '^OVERFLOW_PANES=' "${MULTMUX_REPO_ROOT}/defaults/multmux.conf")"
    printf 'MAIN_PANE_WIDTH="50%%"\n' >"${CONF_FILE}"
    run load_config
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"missing required variable"* ]]
    [[ "${output}" == *"OVERFLOW_PANES"* ]]
    [[ "${output}" == *"${MULTMUX_SYSTEM_CONF}"* ]]
    [[ "${output}" == *"${CONF_FILE}"* ]]
}

@test "load_config: syntax error in the system file fails" {
    mm_install_default_config
    mm_write_system_config 'this is not valid bash((( '
    run load_config
    [ "${status}" -ne 0 ]
}

@test "load_config: syntax error in the user file fails" {
    mm_write_system_config "$(cat "${MULTMUX_REPO_ROOT}/defaults/multmux.conf")"
    printf 'this is not valid bash((( \n' >"${CONF_FILE}"
    run load_config
    [ "${status}" -ne 0 ]
}

@test "cmd_help: shows both configuration locations" {
    run cmd_help
    [[ "${output}" == *"${MULTMUX_SYSTEM_CONF}"* ]]
    [[ "${output}" == *"${CONF_FILE}"* ]]
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
