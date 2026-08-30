#!/usr/bin/env bats
# End-to-end tests for the self-update pipeline (fetch_latest_version,
# perform_update -> install.sh, cmd_update, and the drift check that runs
# through it), against a real local HTTP server standing in for GitHub.
# No real network access is used.
#
# All 'update'/'update --dry-run' invocations here go through a copy of
# multmux pre-installed at $HOME/.local/bin/multmux (mm_install_self),
# matching how a real user runs it (see mm_install_self's comment):
# cmd_update's re-exec of SELF_PATH only picks up the freshly-installed
# code when SELF_PATH is the same file install.sh overwrites.

setup() {
    load '../helpers/common'
    mm_full_isolation_setup
    mm_start_fake_repo_server
    MM_INSTALLED="$(mm_install_self)"
}

teardown() {
    mm_stop_fake_repo_server
    mm_kill_fake_sockets
}

@test "update --dry-run: reports up to date when the fake repo serves the same version" {
    run "${MM_INSTALLED}" update --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"up to date"* ]]
}

@test "update --dry-run: reports a newer version without installing anything" {
    mm_fake_repo_set_version "9.9.9"
    run "${MM_INSTALLED}" update --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"newer multmux is available"* ]]
    [[ "${output}" == *"9.9.9"* ]]
    run "${MM_INSTALLED}" --version
    [[ "${output}" != *"9.9.9"* ]]
}

@test "update --dry-run: fails clearly when the repo server is unreachable" {
    mm_stop_fake_repo_server
    export MULTMUX_REPO_URL="http://127.0.0.1:1"
    run "${MM_INSTALLED}" update --dry-run
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Could not check for updates"* ]]
}

@test "update --dry-run: rejects an unknown option" {
    run "${MM_INSTALLED}" update --bogus
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Unknown option"* ]]
}

@test "update: installs the fake repo's version into ~/.local/bin/multmux" {
    mm_fake_repo_set_version "9.9.9"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    run "${MM_INSTALLED}" --version
    [[ "${output}" == *"9.9.9"* ]]
}

@test "update: installs the default config if none exists yet" {
    rm -f "${HOME}/.config/multmux.conf"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [ -f "${HOME}/.config/multmux.conf" ]
}

@test "update: never touches an existing config file" {
    mm_install_default_config
    echo "# my own custom marker line" >> "${HOME}/.config/multmux.conf"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Config already exists"* ]]
    grep -q "my own custom marker line" "${HOME}/.config/multmux.conf"
}

@test "update: dies clearly when neither curl nor wget is available" {
    mm_install_default_config
    mm_hermetic_path_without curl wget
    ! command -v curl &>/dev/null
    ! command -v wget &>/dev/null
    run "${MM_INSTALLED}" update
    [ "${status}" -ne 0 ]
}

@test "update: fails when the repo server is unreachable (real network failure mode)" {
    mm_install_default_config
    mm_stop_fake_repo_server
    export MULTMUX_REPO_URL="http://127.0.0.1:1"
    run "${MM_INSTALLED}" update
    [ "${status}" -ne 0 ]
}

@test "update: end-to-end drift check catches a real new config line through the freshly-installed binary" {
    mm_install_default_config
    mm_fake_repo_add_inner_conf_line "set -g some-brand-new-real-option 1"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"INNER_CONF is missing"* ]]
    [[ "${output}" == *"some-brand-new-real-option"* ]]
}

@test "update: end-to-end drift check reports nothing for a comment-only difference (regression)" {
    mm_install_default_config
    sed -i.bak 's/hook below/hook/' "${HOME}/.config/multmux.conf"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"is missing lines"* ]]
}

@test "update: the drift check reflects the freshly-installed script's content, not the pre-update one (regression)" {
    # This is the core regression for the "stale in-memory code" bug: the
    # PRE-update installed copy (MM_INSTALLED, i.e. this process's own
    # code) still has the status-interval line. The fake repo's NEWER
    # version being installed does NOT (simulated removal), and neither
    # does the user's config. If cmd_update ran the check with its own
    # stale in-memory logic/defaults instead of re-execing the freshly
    # installed one, this would wrongly report drift.
    mm_install_default_config
    sed -i.bak '/set -g status-interval 1/d' "${MM_FAKE_REPO_DIR}/multmux"
    sed -i.bak '/set -g status-interval 1/d' "${MM_FAKE_REPO_DIR}/defaults/multmux.conf"
    sed -i.bak '/set -g status-interval 1/d' "${HOME}/.config/multmux.conf"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"is missing lines"* ]]
}

@test "update: installs bash completion into the standard bash-completion v2 path" {
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [ -f "${HOME}/.local/share/bash-completion/completions/multmux" ]
    grep -q "_multmux" "${HOME}/.local/share/bash-completion/completions/multmux"
}

@test "update: installs zsh completion into site-functions" {
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [ -f "${HOME}/.local/share/zsh/site-functions/_multmux" ]
    grep -q "#compdef multmux" "${HOME}/.local/share/zsh/site-functions/_multmux"
}

@test "update: warns when bash-completion's dynamic loader isn't active" {
    rm -f "${HOME}/.bashrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"bash-completion's dynamic loader isn't active"* ]]
}

@test "update: stops warning about bash-completion once the user's .bashrc defines the loader" {
    printf '_completion_loader() { :; }\n' > "${HOME}/.bashrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"bash-completion's dynamic loader isn't active"* ]]
}

@test "update: warns when the zsh site-functions dir isn't on \$fpath" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    rm -f "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"is not on your zsh"* ]]
}

@test "update: stops warning about zsh \$fpath once the user's .zshrc adds the site-functions dir" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    printf 'fpath=("%s/.local/share/zsh/site-functions" $fpath)\n' "${HOME}" > "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"is not on your zsh"* ]]
}
