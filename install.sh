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

    # Copy fish config and functions
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/fish-shell/config.fish" "$fish_config_dir/"
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/fish-shell/functions/"*.fish "$fish_config_dir/functions/"

    say "✓ Fish configuration installed"
}

install_system_scripts() {
    say "Installing system scripts..."

    # Copy helper scripts (excluding pacman hooks)
    if [[ -d "$SCRIPT_DIR/system-scripts/snapshot-scripts" ]]; then
        cp "$SCRIPT_DIR/system-scripts/snapshot-scripts/"*.sh /usr/local/sbin/ 2>/dev/null || true
        chmod +x /usr/local/sbin/zfs-*.sh 2>/dev/null || true
    fi

    # Copy systemd units
    cp "$SCRIPT_DIR/system-scripts/systemd-units/"* /etc/systemd/system/
    systemctl daemon-reload

    say "✓ System scripts installed"
}

install_embedded_hooks() {
    say "Installing pacman hooks..."

    install -d /etc/pacman.d/hooks
    install -d /usr/local/sbin

    # Optimized pre-snapshot hook
    cat >/usr/local/sbin/zfs-pre-pacman-snapshot.sh <<'HOOK_SH'
#!/usr/bin/env bash
set -euo pipefail

BE="$(findmnt -no SOURCE /)"
[[ -z "$BE" ]] && exit 1

# Ensure kernels exist before snapshot
if [[ ! -f /boot/vmlinuz-linux-cachyos ]]; then
    for esp in /efi /boot/efi; do
        if [[ -f "$esp/vmlinuz-linux-cachyos" ]]; then
            cp "$esp"/vmlinuz* "$esp"/initramfs* /boot/ 2>/dev/null
            break
        fi
    done || pacman -S --noconfirm linux-cachyos
fi

# Skip if recent snapshot exists (within 3 minutes)
LAST=$(zfs list -Hp -t snapshot -o name,creation "$BE" 2>/dev/null | grep '@pacman-' | tail -1)
if [[ -n "$LAST" ]]; then
    AGE=$(($(date +%s) - $(echo "$LAST" | awk '{print $2}')))
    [[ $AGE -lt 180 ]] && exit 0
fi

# Create snapshot
TAG="pacman-$(date +%Y%m%d-%H%M%S)"
zfs snapshot "${BE}@${TAG}"
echo "[zfs-pre-snap] Created snapshot: ${BE}@${TAG}"
HOOK_SH
    chmod 0755 /usr/local/sbin/zfs-pre-pacman-snapshot.sh

    # Prune snapshots hook
    cat >/usr/local/sbin/zfs-prune-pacman-snapshots.sh <<PRUNE_SH
#!/usr/bin/env bash
set -euo pipefail
KEEP=\${KEEP:-${SNAPSHOT_KEEP}}
BE="\$(findmnt -no SOURCE /)"
[[ -z "\$BE" ]] && exit 1

mapfile -t snaps < <(zfs list -H -t snapshot -o name -s creation | grep "^\${BE}@pacman-")
if (( \${#snaps[@]} > KEEP )); then
    del_count=\$(( \${#snaps[@]} - KEEP ))
    printf "%s\n" "\${snaps[@]:0:del_count}" | xargs -r -n1 zfs destroy
    echo "[zfs-prune] Removed \$del_count old snapshot(s)"
fi
PRUNE_SH
    chmod 0755 /usr/local/sbin/zfs-prune-pacman-snapshots.sh

    # Optional: Copy kernel to ESP helper
    if [[ "${USE_SYSTEMD_BOOT_FALLBACK}" == "true" ]]; then
        cat >/usr/local/sbin/copy-kernel-to-esp.sh <<'COPY_SH'
#!/usr/bin/env bash
set -euo pipefail

ESP="${ESP:-/efi}"
[[ -d "$ESP" ]] || ESP="/boot/efi"
[[ -d "$ESP" ]] || { echo "[copy-kernel] No ESP found"; exit 0; }

# Ensure /boot has kernels (for snapshots)
[[ -f /boot/vmlinuz-linux-cachyos ]] || {
    [[ -f "$ESP/vmlinuz-linux-cachyos" ]] && \
        cp "$ESP"/{vmlinuz,initramfs}* /boot/ 2>/dev/null
}

# Copy to ESP for fallback
mkdir -p "$ESP/EFI/Linux" 2>/dev/null || true
for f in /boot/vmlinuz* /boot/initramfs* /boot/*-ucode.img; do
    [[ -f "$f" ]] && cp -f "$f" "$ESP/" 2>/dev/null || true
done
COPY_SH
        chmod 0755 /usr/local/sbin/copy-kernel-to-esp.sh
    fi

    # Install pacman hooks
    cat >/etc/pacman.d/hooks/00-zfs-pre-snapshot.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = ZFS snapshot of root BE (pre-transaction)
When = PreTransaction
Exec = /usr/local/sbin/zfs-pre-pacman-snapshot.sh
HOOK

    cat >/etc/pacman.d/hooks/99-zfs-prune-snapshots.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Prune old ZFS pacman snapshots
When = PostTransaction
Exec = /usr/local/sbin/zfs-prune-pacman-snapshots.sh
HOOK

    cat >/etc/pacman.d/hooks/90-generate-zbm.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux*
Target = zfsbootmenu

[Action]
Description = Generate ZFSBootMenu images
When = PostTransaction
Exec = /usr/bin/bash -c 'command -v generate-zbm >/dev/null 2>&1 && generate-zbm || true'
HOOK

    if [[ "${USE_SYSTEMD_BOOT_FALLBACK}" == "true" ]]; then
        cat >/etc/pacman.d/hooks/10-copy-kernel-to-esp.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux*

[Action]
Description = Mirror kernel/initramfs to ESP (systemd-boot fallback)
When = PostTransaction
Exec = /usr/local/sbin/copy-kernel-to-esp.sh
HOOK
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
