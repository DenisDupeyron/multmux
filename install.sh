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

info "Installing multmux to ${INSTALL_DIR}/multmux..."
mkdir -p "${INSTALL_DIR}"

# Download to a temp file, then move it into place atomically: 'multmux
# update' may run this while that exact file is still running, and mv
# (rename) doesn't touch the original file's data.
tmp_multmux=$(mktemp)
trap 'rm -f "${tmp_multmux}"' EXIT

if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_URL}/multmux" -o "${tmp_multmux}"
elif command -v wget &>/dev/null; then
    wget -q "${REPO_URL}/multmux" -O "${tmp_multmux}"
else
    die "Neither curl nor wget found."
fi

chmod +x "${tmp_multmux}"
mv "${tmp_multmux}" "${INSTALL_DIR}/multmux"
trap - EXIT

# --- Bundled defaults ---
#
# Not the user's config (see below). This is multmux's own reference
# copy of the shipped defaults, always safe to refresh in place. multmux
# reads it at startup to reconcile/drift-check the user's config.

info "Installing bundled defaults to ${INSTALL_DIR}/defaults/multmux.conf..."
mkdir -p "${INSTALL_DIR}/defaults"

# Same atomic download-then-rename as above, for the same reason.
tmp_defaults=$(mktemp)
trap 'rm -f "${tmp_defaults}"' EXIT

if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_URL}/defaults/multmux.conf" -o "${tmp_defaults}"
elif command -v wget &>/dev/null; then
    wget -q "${REPO_URL}/defaults/multmux.conf" -O "${tmp_defaults}"
else
    die "Neither curl nor wget found."
fi

mv "${tmp_defaults}" "${INSTALL_DIR}/defaults/multmux.conf"
trap - EXIT

# --- Shell completions ---
#
# Not user config either. Regenerated in place on every install/update,
# same atomic download-then-rename pattern as multmux itself.

info "Installing shell completions..."
mkdir -p "${HOME}/.local/share/bash-completion/completions"
mkdir -p "${HOME}/.local/share/zsh/site-functions"

tmp_bash_completion=$(mktemp)
trap 'rm -f "${tmp_bash_completion}"' EXIT
if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_URL}/completions/multmux.bash" -o "${tmp_bash_completion}"
elif command -v wget &>/dev/null; then
    wget -q "${REPO_URL}/completions/multmux.bash" -O "${tmp_bash_completion}"
else
    die "Neither curl nor wget found."
fi
mv "${tmp_bash_completion}" "${HOME}/.local/share/bash-completion/completions/multmux"
trap - EXIT

tmp_zsh_completion=$(mktemp)
trap 'rm -f "${tmp_zsh_completion}"' EXIT
if command -v curl &>/dev/null; then
    curl -fsSL "${REPO_URL}/completions/multmux.zsh" -o "${tmp_zsh_completion}"
elif command -v wget &>/dev/null; then
    wget -q "${REPO_URL}/completions/multmux.zsh" -O "${tmp_zsh_completion}"
else
    die "Neither curl nor wget found."
fi
mv "${tmp_zsh_completion}" "${HOME}/.local/share/zsh/site-functions/_multmux"
trap - EXIT

# --- User config ---
#
# Created once. The user's own file to edit freely, never touched again.

if [[ ! -f "${CONF_DIR}/multmux.conf" ]]; then
    info "Installing default config to ${CONF_DIR}/multmux.conf..."
    cp "${INSTALL_DIR}/defaults/multmux.conf" "${CONF_DIR}/multmux.conf"
else
    info "Config already exists at ${CONF_DIR}/multmux.conf, skipping."
fi

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
    if ! bash -i -c 'declare -F _completion_loader' </dev/null &>/dev/null; then
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
    # Checks the real outcome (does zsh actually wire 'multmux' to a
    # completion function after running the user's own ~/.zshrc, whatever
    # it does), not just whether the directory is on $fpath: a stale
    # cached compinit dump (common with Oh My Zsh/Prezto/'speed up zsh
    # startup' setups that skip rescanning fpath) leaves completion
    # broken even once fpath is correctly set.
    if [[ "$(zsh -i -c 'print -r -- ${_comps[multmux]:-}' </dev/null 2>/dev/null)" != "_multmux" ]]; then
        echo ""
        info "WARNING: zsh doesn't have tab-completion wired up for multmux yet."
        info "Make sure this runs before any 'compinit' call in your ~/.zshrc:"
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
