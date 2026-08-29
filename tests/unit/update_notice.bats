#!/usr/bin/env bats
# Unit tests for the update-notice caching logic: show_update_notice_if_cached
# and read_update_settings. Pure filesystem/state logic, no tmux/network.

setup() {
    load '../helpers/common'
    mm_set_fake_home
    mm_source
    ensure_cache_dir
}

# --- show_update_notice_if_cached ---

@test "show_update_notice_if_cached: silent when there's nothing cached at all" {
    run show_update_notice_if_cached
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "show_update_notice_if_cached: reports and clears a pending 'just auto-updated' marker" {
    touch "${CACHE_DIR}/just_auto_updated"
    run show_update_notice_if_cached
    [[ "${output}" == *"automatically updated"* ]]
    [ ! -f "${CACHE_DIR}/just_auto_updated" ]
}

@test "show_update_notice_if_cached: the auto-updated marker takes priority over a cached latest_version" {
    touch "${CACHE_DIR}/just_auto_updated"
    echo "9.9.9" > "${CACHE_DIR}/latest_version"
    run show_update_notice_if_cached
    [[ "${output}" == *"automatically updated"* ]]
    [[ "${output}" != *"9.9.9"* ]]
}

@test "show_update_notice_if_cached: reports a cached newer version" {
    echo "9.9.9" > "${CACHE_DIR}/latest_version"
    run show_update_notice_if_cached
    [[ "${output}" == *"9.9.9"* ]]
}

@test "show_update_notice_if_cached: an empty latest_version file produces no notice" {
    : > "${CACHE_DIR}/latest_version"
    run show_update_notice_if_cached
    [ -z "${output}" ]
}

# --- read_update_settings ---

@test "read_update_settings: defaults to AUTO_UPDATE=true, 7 days when CONF_FILE is missing" {
    rm -f "${CONF_FILE}"
    read_update_settings
    [ "${AUTO_UPDATE}" = "true" ]
    [ "${AUTO_UPDATE_CHECK_INTERVAL_DAYS}" = "7" ]
}

@test "read_update_settings: reads real values from an installed config" {
    mm_install_default_config
    sed -i.bak 's/^AUTO_UPDATE=.*/AUTO_UPDATE=false/' "${CONF_FILE}"
    sed -i.bak 's/^AUTO_UPDATE_CHECK_INTERVAL_DAYS=.*/AUTO_UPDATE_CHECK_INTERVAL_DAYS=1/' "${CONF_FILE}"
    read_update_settings
    [ "${AUTO_UPDATE}" = "false" ]
    [ "${AUTO_UPDATE_CHECK_INTERVAL_DAYS}" = "1" ]
}

@test "read_update_settings: a broken/unparseable config falls back to defaults instead of dying" {
    printf 'this is not valid bash((( \n' > "${CONF_FILE}"
    run read_update_settings
    [ "${status}" -eq 0 ]
    read_update_settings
    [ "${AUTO_UPDATE}" = "true" ]
    [ "${AUTO_UPDATE_CHECK_INTERVAL_DAYS}" = "7" ]
}

@test "read_update_settings: never used to break 'multmux start' even with a totally missing config" {
    # Sanity/documentation test: read_update_settings itself never dies,
    # unlike load_config. cmd_start relies on this ordering (check_for_update
    # runs before load_config) to still show update notices even when the
    # config is broken in a way load_config itself would reject.
    rm -f "${CONF_FILE}"
    run read_update_settings
    [ "${status}" -eq 0 ]
}
