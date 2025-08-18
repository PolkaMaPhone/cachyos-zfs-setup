#!/usr/bin/env bash
# all-in-one.sh - bootstrap CachyOS ZFS setup
#
# Fetches the repository, runs install.sh, zbm-setup.sh, and validate-setup.sh
# sequentially. Intended for usage via:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/cachyos-zfs-setup/main/all-in-one.sh | sudo bash -s -- [ESP_DEVICE]
#
# Environment variables:
#   REPO_URL  - Git repository to clone (default: https://github.com/CachyOS/cachyos-zfs-setup.git)
#   BRANCH    - Branch to checkout (default: main)
#   WORKDIR   - Directory to clone into (default: /tmp/cachyos-zfs-setup)

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/CachyOS/cachyos-zfs-setup.git}"
BRANCH="${BRANCH:-main}"
WORKDIR="${WORKDIR:-/tmp/cachyos-zfs-setup}"

# Fresh clone
rm -rf "$WORKDIR"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORKDIR"
cd "$WORKDIR"

# Warn if ESP argument looks suspicious
./esp-validate "$@"

# Run main installation
./install.sh

# Run ZFSBootMenu setup, forwarding any user arguments (e.g., ESP device)
./system-scripts/zbm-setup.sh "$@"

# Validate final setup
./validate-setup.sh
