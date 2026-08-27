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

REPO_URL="https://raw.githubusercontent.com/DenisDupeyron/multmux/main"
INSTALL_DIR="${HOME}/.local/bin"
CONF_DIR="${HOME}/.config"
TMUX_CONF_DIR="${HOME}/.config/tmux"

info() { echo "[multmux] $*"; }
die() { echo "[multmux] ERROR: $*" >&2; exit 1; }

# --- Dependency checks ---

info "Checking dependencies..."

# Bash version
bash_major="${BASH_VERSINFO[0]}"
if [[ "${bash_major}" -lt 4 ]]; then
    die "bash >= 4 required (found ${BASH_VERSION}). Install with: brew install bash"
fi

# tmux
if ! command -v tmux &>/dev/null; then
    die "tmux is not installed. Install with: brew install tmux (macOS) or apt install tmux (Linux)"
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

# Download to a temp file first, then move it into place atomically. This
# matters because 'multmux update' may run this installer while the
# currently-running multmux script is that very file: overwriting it in
# place could corrupt the running process. mv (rename) does not touch the
# original file's data, so a process already reading it is unaffected.
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

# --- Config ---

if [[ ! -f "${CONF_DIR}/multmux.conf" ]]; then
    info "Installing default config to ${CONF_DIR}/multmux.conf..."
    if command -v curl &>/dev/null; then
        curl -fsSL "${REPO_URL}/defaults/multmux.conf" -o "${CONF_DIR}/multmux.conf"
    else
        wget -q "${REPO_URL}/defaults/multmux.conf" -O "${CONF_DIR}/multmux.conf"
    fi
else
    info "Config already exists at ${CONF_DIR}/multmux.conf, skipping."
fi

# --- Optional: tmux.conf ---

if [[ ! -f "${TMUX_CONF_DIR}/tmux.conf" && ! -f "${HOME}/.tmux.conf" ]]; then
    info "No tmux config found. Installing recommended tmux.conf to ${TMUX_CONF_DIR}/tmux.conf..."
    mkdir -p "${TMUX_CONF_DIR}"
    if command -v curl &>/dev/null; then
        curl -fsSL "${REPO_URL}/defaults/tmux.conf" -o "${TMUX_CONF_DIR}/tmux.conf"
    else
        wget -q "${REPO_URL}/defaults/tmux.conf" -O "${TMUX_CONF_DIR}/tmux.conf"
    fi
else
    info "tmux config already exists, skipping."
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

info "Done! Run 'multmux start' to begin."
