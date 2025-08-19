#!/usr/bin/env bash
# all-in-one.sh - bootstrap CachyOS ZFS setup
#
# Fetches the repository, runs install.sh, zbm-setup.sh, and validate-setup.sh
# sequentially. Intended for usage via:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/cachyos-zfs-setup/main/all-in-one.sh | sudo bash -s -- [ESP_DEVICE]
#
# Environment variables:
#   REPO_URL  - Git repository to clone (default: https://github.com/polkamaphone/cachyos-zfs-setup.git)
#   BRANCH    - Branch to checkout (default: main)
#   WORKDIR   - Directory to clone into (default: /tmp/cachyos-zfs-setup)

set -euo pipefail

# Utility functions for consistent messaging
say() { printf "\033[1;32m[all-in-one]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[all-in-one]\033[0m %s\n" "$*"; }

REPO_URL="${REPO_URL:-https://github.com/polkamaphone/cachyos-zfs-setup.git}"
BRANCH="${BRANCH:-main}"
WORKDIR="${WORKDIR:-/tmp/cachyos-zfs-setup}"

# Check for sudo/root privileges and warn user if not present
check_sudo_and_warn() {
    if [[ $EUID -ne 0 ]]; then
        warn "This script is not running with root privileges."
        warn "While all-in-one.sh itself doesn't require sudo, the downstream scripts will need it:"
        warn "  • install.sh requires root to install system scripts and pacman hooks"
        warn "  • zbm-setup.sh requires root to install packages and configure ZFSBootMenu"
        warn ""
        warn "Without root privileges, the installation will fail when these scripts run."
        warn "Consider running: sudo $0 $*"
        warn ""
        
        local response
        read -rp "Do you want to continue anyway? (y/N): " response
        case "${response,,}" in
            y|yes)
                warn "Proceeding without root privileges - expect failures in downstream scripts..."
                ;;
            *)
                warn "Aborting at user request. Re-run with sudo for best results."
                exit 1
                ;;
        esac
    else
        say "Running with root privileges - good!"
    fi
}

# Check for sudo/root and warn if not present
check_sudo_and_warn "$@"

# Fresh clone
rm -rf "$WORKDIR"
GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORKDIR"
cd "$WORKDIR"

# Warn if ESP argument looks suspicious
./esp-validate "$@"

# Run main installation
./install.sh

# Run ZFSBootMenu setup, forwarding any user arguments (e.g., ESP device)
./system-scripts/zbm-setup.sh "$@"

# Validate final setup
./validate-setup.sh
