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

# Overridable so tests can point this at a local fake server instead of
# real GitHub (see tests/), same pattern used by multmux itself.
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

# --- Bundled defaults ---
#
# NOT the user's config (that is the separate, never-overwritten section
# below). This is multmux's own internal reference copy of the shipped
# defaults, installed right next to the script itself, exactly like the
# multmux script file itself: nobody expects to hand-edit it or keep
# changes across an update, so it's always safe to refresh in place.
# multmux reads it at startup to reconcile/drift-check the user's config
# against whatever this exact installed version actually ships, without
# embedding a second, easily drifting copy inside the script itself, and
# without needing a separate network fetch at reconciliation time: it's
# already here from install.

info "Installing bundled defaults to ${INSTALL_DIR}/defaults/multmux.conf..."
mkdir -p "${INSTALL_DIR}/defaults"

# Same atomic download-then-rename as multmux itself above, for the same
# reason: a concurrently running multmux could be reading this file while
# this installer overwrites it.
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

# --- User config ---
#
# Only ever created once: this is the user's own file to edit freely,
# never touched again by multmux or by this installer on later updates.

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

info "Done! Run 'multmux start' to begin."
