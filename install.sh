#!/usr/bin/env bash

# Copyright (C) 2026 Denis Dupeyron
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

# multmux installer
# Usage: curl -fsSL https://raw.githubusercontent.com/DenisDupeyron/multmux/main/install.sh | bash

# Overridable for tests (see tests/), same pattern used by multmux itself.
REPO_URL="${MULTMUX_REPO_URL:-https://raw.githubusercontent.com/DenisDupeyron/multmux/main}"
INSTALL_DIR="${HOME}/.local/bin"
CONF_DIR="${HOME}/.config"

REQUIRED_CONFIG_VARS=(START_DIR MAIN_PANE_WIDTH OVERFLOW_PANES INNER_SESSIONS BASE_CONF OUTER_CONF INNER_CONF SESSION_NAME_COMPONENT_MAX SESSION_NAME_TOTAL_MAX)
tmp_multmux=""
tmp_defaults=""
tmp_bash_completion=""
tmp_zsh_completion=""

cleanup() {
    rm -f "${tmp_multmux}" "${tmp_defaults}" "${tmp_bash_completion}" "${tmp_zsh_completion}"
}
trap cleanup EXIT

parse_config_blocks() {
    local content="$1"
    CONFIG_BLOCK_NAMES=()
    declare -gA CONFIG_BLOCK_TEXT=()
    declare -gA CONFIG_BLOCK_END_LINE=()

    local pending="" varname="" in_heredoc=false current="" line_no=0 line
    while IFS= read -r line; do
        line_no=$((line_no + 1))
        if [[ "${in_heredoc}" == true ]]; then
            current+="${line}"$'\n'
            if [[ "${line}" == ")" ]]; then
                CONFIG_BLOCK_TEXT["${varname}"]="${current}"
                CONFIG_BLOCK_END_LINE["${varname}"]="${line_no}"
                CONFIG_BLOCK_NAMES+=("${varname}")
                in_heredoc=false
                current=""
            fi
            continue
        fi
        if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            varname="${BASH_REMATCH[1]}"
            current="${pending}${line}"$'\n'
            pending=""
            if [[ "${line}" == *"<<"*"'EOF'" ]]; then
                in_heredoc=true
            else
                CONFIG_BLOCK_TEXT["${varname}"]="${current}"
                CONFIG_BLOCK_END_LINE["${varname}"]="${line_no}"
                CONFIG_BLOCK_NAMES+=("${varname}")
                current=""
            fi
            continue
        fi
        pending+="${line}"$'\n'
    done <<<"${content}"
}

reconcile_missing_vars() {
    local -a missing=("$@")
    ((${#missing[@]} > 0)) || return 1

    local default_content
    default_content="$(cat "${tmp_defaults}")"
    parse_config_blocks "${default_content}"
    local -a default_names=("${CONFIG_BLOCK_NAMES[@]}")
    local -A default_text=()
    local var
    for var in "${default_names[@]}"; do
        default_text["${var}"]="${CONFIG_BLOCK_TEXT[${var}]}"
    done
    for var in "${missing[@]}"; do
        [[ -n "${default_text[${var}]+x}" ]] || die "Bundled defaults are missing required variable: ${var}"
    done

    local user_content
    user_content="$(cat "${CONF_DIR}/multmux.conf")"
    parse_config_blocks "${user_content}"
    local -A user_end_line=()
    for var in "${CONFIG_BLOCK_NAMES[@]}"; do
        user_end_line["${var}"]="${CONFIG_BLOCK_END_LINE[${var}]}"
    done
    local -A default_index=()
    local i
    for ((i = 0; i < ${#default_names[@]}; i++)); do
        default_index["${default_names[i]}"]="${i}"
    done
    local -A insert_after=()
    for var in "${missing[@]}"; do
        local idx="${default_index[${var}]}" anchor_line=0
        for ((i = idx - 1; i >= 0; i--)); do
            local candidate="${default_names[i]}"
            if [[ -n "${user_end_line[${candidate}]+x}" ]]; then
                anchor_line="${user_end_line[${candidate}]}"
                break
            fi
        done
        insert_after["${anchor_line}"]+="${default_text[${var}]}"
    done
    local -a user_lines=()
    mapfile -t user_lines < <(printf '%s' "${user_content}")
    local new_content="" n
    [[ -n "${insert_after[0]+x}" ]] && new_content+="${insert_after[0]}"
    for ((n = 0; n < ${#user_lines[@]}; n++)); do
        new_content+="${user_lines[n]}"$'\n'
        local line_no=$((n + 1))
        [[ -n "${insert_after[${line_no}]+x}" ]] && new_content+="${insert_after[${line_no}]}"
    done
    printf '%s' "${new_content}" >"${CONF_DIR}/multmux.conf"

    info "Added settings from the current defaults to ${CONF_DIR}/multmux.conf:"
    for var in "${missing[@]}"; do
        printf '    + %s\n' "${var}"
    done
}

migrate_config() {
    local config_file="${CONF_DIR}/multmux.conf"
    [[ -f "${config_file}" ]] || return 0

    local evaluated_missing
    evaluated_missing="$(
        bash -c '
            source "$1" >/dev/null || exit $?
            shift
            for var; do
                declare -p "${var}" &>/dev/null || printf "%s\n" "${var}"
            done
        ' _ "${config_file}" "${REQUIRED_CONFIG_VARS[@]}"
    )" || die "Could not load configuration: ${config_file}"

    local -a missing=()
    local var
    while IFS= read -r var; do
        [[ -n "${var}" ]] && missing+=("${var}")
    done <<<"${evaluated_missing}"
    reconcile_missing_vars "${missing[@]}" || true
}

config_var_value() {
    local config_text="$1" var="$2"
    (
        eval "${config_text}" &>/dev/null
        printf '%s' "${!var}"
    ) 2>/dev/null || true
}
report_block_drift() {
    local default_config="$1" conf_file="$2" block="$3"
    local default_value user_value
    default_value="$(config_var_value "${default_config}" "${block}")"
    user_value="$(config_var_value "$(cat "${conf_file}")" "${block}")"
    local -a missing_lines=()
    local line already user_line
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        already=false
        while IFS= read -r user_line; do
            [[ "${user_line}" == "${line}" ]] && { already=true; break; }
        done <<<"${user_value}"
        [[ "${already}" == false ]] && missing_lines+=("${line}")
    done <<<"${default_value}"
    if ((${#missing_lines[@]} > 0)); then
        info "WARNING: ${conf_file}'s ${block} is missing lines present in the current defaults:"
        for line in "${missing_lines[@]}"; do
            printf '    %s\n' "${line}"
        done
    fi
}

check_tmux_config_drift() {
    [[ -f "${CONF_DIR}/multmux.conf" ]] || return 0
    local default_config
    default_config="$(cat "${tmp_defaults}")"
    local block
    for block in BASE_CONF OUTER_CONF INNER_CONF; do
        report_block_drift "${default_config}" "${CONF_DIR}/multmux.conf" "${block}"
    done
}

info() { echo "[multmux] $*"; }
die() {
    echo "[multmux] ERROR: $*" >&2
    exit 1
}

# --- Dependency checks ---

info "Checking dependencies..."

# Bash version
bash_major="${BASH_VERSINFO[0]}"
if [[ "${bash_major}" -lt 4 ]]; then
    die "bash >= 4 required (found ${BASH_VERSION})."
fi

# tmux
if ! command -v tmux &>/dev/null; then
    die "tmux is not installed."
fi

tmux_version=$(tmux -V | grep -oE '[0-9]+\.[0-9]+')
required_version="3.2"
if [[ "$(printf '%s\n' "${required_version}" "${tmux_version}" | sort -V | head -1)" != "${required_version}" ]]; then
    die "tmux >= ${required_version} required (found ${tmux_version})"
fi

# seq (should be available everywhere, but check)
if ! command -v seq &>/dev/null; then
    die "seq is not installed."
fi

info "Dependencies OK (bash ${BASH_VERSION}, tmux ${tmux_version})"

# --- Install ---

info "Preparing multmux for ${INSTALL_DIR}/multmux..."
mkdir -p "${INSTALL_DIR}"

# Stage every downloaded artifact before changing the installed executable.
# A failed update then leaves the prior runtime and user configuration usable.
tmp_multmux=$(mktemp)
if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_URL}/multmux" -o "${tmp_multmux}"
elif command -v wget &>/dev/null; then
    wget -q "${REPO_URL}/multmux" -O "${tmp_multmux}"
else
    die "Neither curl nor wget found."
fi
chmod +x "${tmp_multmux}"

info "Downloading current defaults..."
tmp_defaults=$(mktemp)
if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_URL}/defaults/multmux.conf" -o "${tmp_defaults}"
elif command -v wget &>/dev/null; then
    wget -q "${REPO_URL}/defaults/multmux.conf" -O "${tmp_defaults}"
else
    die "Neither curl nor wget found."
fi

info "Preparing shell completions..."
tmp_bash_completion=$(mktemp)
if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_URL}/completions/multmux.bash" -o "${tmp_bash_completion}"
elif command -v wget &>/dev/null; then
    wget -q "${REPO_URL}/completions/multmux.bash" -O "${tmp_bash_completion}"
else
    die "Neither curl nor wget found."
fi

tmp_zsh_completion=$(mktemp)
if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_URL}/completions/multmux.zsh" -o "${tmp_zsh_completion}"
elif command -v wget &>/dev/null; then
    wget -q "${REPO_URL}/completions/multmux.zsh" -O "${tmp_zsh_completion}"
else
    die "Neither curl nor wget found."
fi

# --- User config ---
#
# Created from the temporary defaults on first install. Later installs merge
# only required top-level settings and report missing tmux directives.

mkdir -p "${CONF_DIR}"
if [[ ! -f "${CONF_DIR}/multmux.conf" ]]; then
    info "Installing default config to ${CONF_DIR}/multmux.conf..."
    cp "${tmp_defaults}" "${CONF_DIR}/multmux.conf"
else
    migrate_config
fi
check_tmux_config_drift

info "Installing multmux..."
mv "${tmp_multmux}" "${INSTALL_DIR}/multmux"
tmp_multmux=""

mkdir -p "${HOME}/.local/share/bash-completion/completions"
mkdir -p "${HOME}/.local/share/zsh/site-functions"
mv "${tmp_bash_completion}" "${HOME}/.local/share/bash-completion/completions/multmux"
tmp_bash_completion=""
mv "${tmp_zsh_completion}" "${HOME}/.local/share/zsh/site-functions/_multmux"
tmp_zsh_completion=""

# --- Version ---

installed_version=$("${INSTALL_DIR}/multmux" --version 2>/dev/null | awk '{print $2}')
if [[ -n "${installed_version}" ]]; then
    info "Installed multmux version ${installed_version}."
fi

# --- PATH check ---

if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    echo ""
    info "WARNING: ${INSTALL_DIR} is not in your PATH."
    info "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
    echo ""
fi

# --- Shell completion activation check ---
#
# Best-effort: the files installed above are inert until the user's own
# shell actually loads them. Checked against a real interactive shell (rc
# files and any distro-level wiring included), not just this installer's,
# and only for the shell the user actually uses (their $SHELL), so a
# zsh-only user is never warned about bash-completion just because bash
# happens to also be installed, or vice versa.
# Runs on every install/update until the user fixes it on their end.

if [[ "${SHELL:-}" == */bash ]] && command -v bash &>/dev/null; then
    if ! bash -li -c 'declare -F _completion_loader' </dev/null &>/dev/null; then
        echo ""
        info "WARNING: bash-completion's dynamic loader isn't active in your bash."
        info "multmux tab-completion won't work until you install/enable bash-completion,"
        info "or add this to your ~/.bashrc:"
        echo ""
        echo "  source ~/.local/share/bash-completion/completions/multmux"
        echo ""
    fi
fi

if [[ "${SHELL:-}" == */zsh ]] && command -v zsh &>/dev/null; then
    # -li, not just -i: a real Terminal/iTerm window is a LOGIN shell, so
    # it also sources ~/.zprofile (Homebrew's shellenv and similar often
    # live there, not ~/.zshrc). Checks the real outcome (does zsh
    # actually wire 'multmux' to a completion function after running the
    # user's own startup files, whatever they do), not just whether the
    # directory is on $fpath: a stale cached compinit dump (common with
    # Oh My Zsh/Prezto/'speed up zsh startup' setups that skip rescanning
    # fpath) leaves completion broken even once fpath is correctly set.
    #
    # This execution-based check alone is not reliable: 'zsh -li -c' does
    # not faithfully reproduce Oh My Zsh's compinit timing, and can
    # report success even when a genuinely fresh interactive shell does
    # not (confirmed directly against a real Oh My Zsh setup). So also
    # check textually whether ~/.zshrc adds this fpath entry after
    # sourcing Oh My Zsh, which hides its own compinit call and is the
    # single most common cause of this exact false-positive.
    zshrc="${HOME}/.zshrc"
    omz_before_fpath=false
    if [[ -f "${zshrc}" ]]; then
        omz_line=$(grep -n 'source.*oh-my-zsh\.sh' "${zshrc}" 2>/dev/null | head -1 | cut -d: -f1)
        fpath_line=$(grep -n 'site-functions' "${zshrc}" 2>/dev/null | head -1 | cut -d: -f1)
        if [[ -n "${omz_line}" && -n "${fpath_line}" ]] && ((fpath_line > omz_line)); then
            omz_before_fpath=true
        fi
    fi

    if [[ "${omz_before_fpath}" == true ]] || [[ "$(zsh -li -c 'print -r -- ${_comps[multmux]:-}' </dev/null 2>/dev/null)" != "_multmux" ]]; then
        echo ""
        info "WARNING: zsh doesn't have tab-completion wired up for multmux yet."
        if [[ "${omz_before_fpath}" == true ]]; then
            info "Your ~/.zshrc adds this fpath entry AFTER 'source \$ZSH/oh-my-zsh.sh',"
            info "which is where Oh My Zsh calls compinit. Move this line ABOVE that"
            info "'source' line instead:"
        else
            info "Make sure this runs before any 'compinit' call in your ~/.zshrc"
            info "(for Oh My Zsh, that means before 'source \$ZSH/oh-my-zsh.sh'):"
        fi
        echo ""
        echo "  fpath=(~/.local/share/zsh/site-functions \$fpath)"
        echo ""
        info "Already there and still not working? zsh cached an older completion"
        info "list. Force a rebuild:"
        echo ""
        echo "  rm -f ~/.zcompdump* && exec zsh"
        echo ""
    fi
fi

info "Done! Run 'multmux start' to begin."
