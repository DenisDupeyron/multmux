#!/usr/bin/env bats
# End-to-end tests for the self-update pipeline against a local fake HTTP
# server. Updates install a fresh executable, migrate required top-level
# settings, and report missing tmux directives without retaining defaults.

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

@test "update: creates configuration and its parent directory when absent" {
    rm -rf "${HOME}/.config"

    run "${MM_INSTALLED}" update

    [ "${status}" -eq 0 ]
    [ -f "${HOME}/.config/multmux.conf" ]
}

@test "update: preserves custom configuration content" {
    mm_install_default_config
    echo "# my own custom marker line" >> "${HOME}/.config/multmux.conf"

    run "${MM_INSTALLED}" update

    [ "${status}" -eq 0 ]
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

@test "update: download failure leaves the current executable and config unchanged" {
    mm_install_default_config
    sed -i.bak '/^OVERFLOW_PANES=/d' "${HOME}/.config/multmux.conf"
    mm_fake_repo_set_version "9.9.9"
    rm "${MM_FAKE_REPO_DIR}/completions/multmux.zsh"

    run "${MM_INSTALLED}" update

    [ "${status}" -ne 0 ]
    run "${MM_INSTALLED}" --version
    [[ "${output}" != *"9.9.9"* ]]
    ! grep -q '^OVERFLOW_PANES=' "${HOME}/.config/multmux.conf"
}

@test "update: migrates missing required settings and reports tmux drift" {
    mm_install_default_config
    sed -i.bak '/^OVERFLOW_PANES=/d' "${HOME}/.config/multmux.conf"
    mm_fake_repo_add_inner_conf_line "set -g some-brand-new-real-option 1"

    run "${MM_INSTALLED}" update

    [ "${status}" -eq 0 ]
    grep -q '^OVERFLOW_PANES=' "${HOME}/.config/multmux.conf"
    [[ "${output}" == *"Added settings from the current defaults"* ]]
    [[ "${output}" == *"INNER_CONF is missing"* ]]
    [[ "${output}" == *"some-brand-new-real-option"* ]]
    [ ! -e "${HOME}/.local/bin/defaults" ]
}

@test "update: evaluates configuration before identifying missing settings" {
    mm_install_default_config
    sed -i.bak '/^OVERFLOW_PANES=/d' "${HOME}/.config/multmux.conf"
    cat >>"${HOME}/.config/multmux.conf" <<'EOF'
if false; then
OVERFLOW_PANES=3
fi
EOF

    run "${MM_INSTALLED}" update

    [ "${status}" -eq 0 ]
    [ "$(grep -c '^OVERFLOW_PANES=' "${HOME}/.config/multmux.conf")" -eq 2 ]
}

@test "update: end-to-end drift check reports nothing for a comment-only difference (regression)" {
    mm_install_default_config
    sed -i.bak 's/hook below/hook/' "${HOME}/.config/multmux.conf"
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
    export SHELL=/bin/bash
    rm -f "${HOME}/.bashrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"bash-completion's dynamic loader isn't active"* ]]
}

@test "update: stops warning about bash-completion once the user's .bashrc defines the loader" {
    export SHELL=/bin/bash
    printf '_completion_loader() { :; }\n' > "${HOME}/.bashrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"bash-completion's dynamic loader isn't active"* ]]
}

@test "update: never warns about bash-completion when the user's shell isn't bash (regression)" {
    # SHELL=zsh, no .bashrc at all: the bash-completion check must not run
    # just because the bash binary happens to be installed too.
    export SHELL=/bin/zsh
    rm -f "${HOME}/.bashrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"bash-completion"* ]]
}

@test "update: warns when zsh has no completion setup at all" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    export SHELL=/bin/zsh
    rm -f "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"doesn't have tab-completion wired up"* ]]
}

@test "update: still warns if \$fpath is set but compinit is never called (regression: fpath alone isn't enough)" {
    # A fpath-membership-only check would have wrongly suppressed this
    # warning: the directory is on fpath, but nothing ever wires
    # 'multmux' to a completion function without a real compinit call.
    command -v zsh &>/dev/null || skip "zsh not installed"
    export SHELL=/bin/zsh
    printf 'fpath=("%s/.local/share/zsh/site-functions" $fpath)\n' "${HOME}" > "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"doesn't have tab-completion wired up"* ]]
}

@test "update: stops warning once the user's .zshrc sets fpath and runs compinit" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    export SHELL=/bin/zsh
    {
        printf 'fpath=("%s/.local/share/zsh/site-functions" $fpath)\n' "${HOME}"
        printf 'autoload -Uz compinit\n'
        printf 'compinit -u\n'
    } > "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"doesn't have tab-completion wired up"* ]]
}

@test "update: does not warn when fpath/compinit live in .zprofile instead of .zshrc (real terminal is a login shell)" {
    # A real Terminal/iTerm window runs a LOGIN shell, sourcing
    # ~/.zprofile as well as ~/.zshrc (Homebrew's shellenv and similar
    # setup often live in .zprofile). A non-login check would miss this
    # and warn even though completion genuinely works for the user.
    command -v zsh &>/dev/null || skip "zsh not installed"
    export SHELL=/bin/zsh
    {
        printf 'fpath=("%s/.local/share/zsh/site-functions" $fpath)\n' "${HOME}"
        printf 'autoload -Uz compinit\n'
        printf 'compinit -u\n'
    } > "${HOME}/.zprofile"
    rm -f "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"doesn't have tab-completion wired up"* ]]
}

@test "update: warns specifically about Oh My Zsh ordering when fpath comes after 'source \$ZSH/oh-my-zsh.sh' (regression)" {
    # The real-world bug: the execution-based _comps check alone can give
    # a false "it's fine" for this exact ordering mistake ('zsh -li -c'
    # does not faithfully reproduce Oh My Zsh's compinit timing, verified
    # directly against a real Oh My Zsh setup), so the textual ordering
    # check must catch it independently of that check's result.
    command -v zsh &>/dev/null || skip "zsh not installed"
    export SHELL=/bin/zsh
    {
        echo 'export ZSH="$HOME/.oh-my-zsh"'
        echo 'plugins=()'
        echo 'source $ZSH/oh-my-zsh.sh'
        printf 'fpath=(%s/.local/share/zsh/site-functions $fpath)\n' "${HOME}"
    } > "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"doesn't have tab-completion wired up"* ]]
    [[ "${output}" == *"oh-my-zsh.sh"* ]]
}

@test "update: does not fire the Oh My Zsh ordering message when fpath comes before 'source \$ZSH/oh-my-zsh.sh'" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    export SHELL=/bin/zsh
    {
        echo 'export ZSH="$HOME/.oh-my-zsh"'
        echo 'plugins=()'
        printf 'fpath=(%s/.local/share/zsh/site-functions $fpath)\n' "${HOME}"
        echo 'source $ZSH/oh-my-zsh.sh'
    } > "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"AFTER 'source"* ]]
}

@test "update: never warns about zsh \$fpath when the user's shell isn't zsh (regression)" {
    export SHELL=/bin/bash
    printf '_completion_loader() { :; }\n' > "${HOME}/.bashrc"
    rm -f "${HOME}/.zshrc"
    run "${MM_INSTALLED}" update
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"zsh"* ]]
}
