#!/bin/bash
# CachyOS ZFS Setup - Main installer (Optimized)
# Simplified with embedded hooks and streamlined logic

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="/home/$SUDO_USER"

# Configuration defaults
: "${USE_SYSTEMD_BOOT_FALLBACK:=true}"
: "${SNAPSHOT_KEEP:=20}"
: "${KERNEL_BASENAME:=linux-cachyos}"

# Shared hook helpers
source "$SCRIPT_DIR/system-scripts/hooks-common.sh"

echo "=== CachyOS ZFS Setup Installation ==="

# Utility functions
say() { printf "\033[1;32m[install]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[install]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[install]\033[0m %s\n" "$*" >&2; exit 1; }

# Unified kernel management function
ensure_kernels() {
    local target="${1:-/boot}"
    local kernel_file="$target/vmlinuz-${KERNEL_BASENAME}"

    # Skip if already present
    [[ -f "$kernel_file" ]] && return 0

    say "Ensuring kernel files in $target..."

    # Try copying from common ESP locations
    for esp in /efi /boot/efi; do
        if [[ -f "$esp/vmlinuz-${KERNEL_BASENAME}" ]]; then
            cp "$esp/vmlinuz-${KERNEL_BASENAME}" "$target/"
            cp "$esp/initramfs-${KERNEL_BASENAME}"*.img "$target/" 2>/dev/null || true
            cp "$esp/"*-ucode.img "$target/" 2>/dev/null || true
            say "✓ Kernel files copied from $esp"
            return 0
        fi
    done

    # Fall back to package installation
    say "Installing kernel package to populate $target..."
    pacman -S --noconfirm "${KERNEL_BASENAME}"
    say "✓ Kernel package installed"
}

cleanup_unbootable_snapshots() {
    say "Checking for unbootable snapshots..."

    local root_dataset=$(findmnt -no SOURCE / 2>/dev/null || echo "")
    [[ -z "$root_dataset" ]] && return 0

    local count=0
    while IFS= read -r snapshot; do
        local temp_mount="/tmp/zfs-check-$$"
        mkdir -p "$temp_mount"

        if mount -t zfs -o ro "$snapshot" "$temp_mount" 2>/dev/null; then
            if [[ ! -f "$temp_mount/boot/vmlinuz-${KERNEL_BASENAME}" ]]; then
                umount "$temp_mount" 2>/dev/null || true
                zfs destroy "$snapshot" 2>/dev/null && ((count++)) || true
            else
                umount "$temp_mount" 2>/dev/null || true
            fi
        fi

        rmdir "$temp_mount" 2>/dev/null || true
    done < <(zfs list -H -t snapshot -o name -r "$root_dataset" 2>/dev/null | grep "@pacman-")

    [[ $count -gt 0 ]] && say "✓ Removed $count unbootable snapshot(s)" || say "✓ No unbootable snapshots found"
}

install_fish_config() {
    say "Installing Fish shell configuration..."

    local fish_config_dir="$USER_HOME/.config/fish"
    sudo -u "$SUDO_USER" mkdir -p "$fish_config_dir/functions"
    sudo -u "$SUDO_USER" mkdir -p "$fish_config_dir/conf.d"

    # Copy only ZFS functions (zfs-*.fish)
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/fish-shell/functions/"zfs-*.fish "$fish_config_dir/functions/"
    
    # Copy conf.d snippets for environment and abbreviations
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/fish-shell/conf.d/"*.fish "$fish_config_dir/conf.d/"

    say "✓ Fish configuration installed"
}

install_system_scripts() {
    say "Installing system scripts..."

    # Copy systemd units
    cp "$SCRIPT_DIR/system-scripts/systemd-units/"* /etc/systemd/system/
    systemctl daemon-reload

    say "✓ System scripts installed"
}

install_embedded_hooks() {
    say "Installing pacman hooks..."

    install_pre_snapshot_hook
    install_prune_snapshots_hook
    install_generate_zbm_hook

    if [[ "${USE_SYSTEMD_BOOT_FALLBACK}" == "true" ]]; then
        install_copy_kernel_to_esp_hook
    fi

    say "✓ Pacman hooks installed"
}

enable_zfs_automation() {
    say "Enabling ZFS automation..."

    # Try to detect the pool name if not set
    local pool="${POOL:-$(zpool list -H -o name 2>/dev/null | head -n1)}"

    if [[ -n "$pool" ]]; then
        systemctl enable --now "zpool-scrub@${pool}.timer" 2>/dev/null && \
            say "✓ Monthly scrub enabled for pool: $pool" || \
            warn "Could not enable scrub timer for pool: $pool"
    else
        warn "No ZFS pool detected - scrub timer not enabled"
    fi
}

set_fish_default() {
    say "Setting Fish as default shell..."

    if [[ "$SUDO_USER" != "root" ]] && ! grep -q "/usr/bin/fish" /etc/passwd | grep "$SUDO_USER"; then
        chsh -s /usr/bin/fish "$SUDO_USER" && \
            say "✓ Fish set as default shell for $SUDO_USER" || \
            warn "Could not set Fish as default shell"
    else
        say "✓ Fish already default or user is root"
    fi
}

main() {
    # Validate environment
    [[ $EUID -eq 0 ]] || die "Run as root (sudo ./install.sh)"
    [[ -n "${SUDO_USER:-}" ]] || die "Must use sudo, not direct root"

    # Core installation
    install_fish_config
    install_system_scripts
    install_embedded_hooks
    enable_zfs_automation
    set_fish_default

    # Post-install cleanup if ZBM is configured
    if [[ -f /etc/zfsbootmenu/config.yaml ]]; then
        ensure_kernels /boot
        cleanup_unbootable_snapshots
    fi

    # Summary
    echo ""
    say "=== Installation Complete ==="
    echo ""

    if [[ -f /etc/zfsbootmenu/config.yaml ]]; then
        echo "Next steps:"
        echo "1. Log out and back in (or run 'exec fish') to use Fish shell"
        echo "2. Test ZFS functions: 'zfs-config-show'"
        echo "3. Verify setup: './validate-setup.sh'"
    else
        echo "Next steps:"
        echo "1. Configure ZFSBootMenu: sudo ./system-scripts/zbm-setup.sh /dev/your-esp-device"
        echo "2. Verify setup: './validate-setup.sh'"
        echo "3. Log out and back in to use Fish shell"
    fi
}

main "$@"
