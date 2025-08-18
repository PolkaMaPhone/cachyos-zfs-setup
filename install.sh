#!/bin/bash
# CachyOS ZFS Setup - Main installer
# Optimized to prevent unbootable snapshots during initial setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="/home/$SUDO_USER"

echo "=== CachyOS ZFS Setup Installation ==="
# Stage pacman hook assets to a fixed location so finish script is repo-agnostic
stage_pacman_hooks() {
    local REPO_ROOT="$SCRIPT_DIR"
    local SRC_DIR="$REPO_ROOT/system-scripts/pacman-hooks"
    local DATA_DIR="/usr/local/share/cachyos-zfs-setup/pacman-hooks"

    install -d "$DATA_DIR"
    if [[ -d "$SRC_DIR" ]]; then
        install -m 0644 "$SRC_DIR"/*.hook "$DATA_DIR"/
        echo "Staged pacman hooks to $DATA_DIR"
    else
        echo "Warning: $SRC_DIR not found; pacman hooks will need to be supplied later"
    fi
}


# Function to ensure kernels are in /boot BEFORE hooks are active
ensure_kernels_in_boot() {
    echo "Ensuring kernel files are in /boot before enabling hooks..."

    # Check if kernels are already in /boot
    if [[ -f /boot/vmlinuz-linux-cachyos ]]; then
        echo "✓ Kernel files already in /boot"
        return 0
    fi

    # Try to copy from ESP first
    for esp_dir in /efi /boot/efi; do
        if [[ -f "$esp_dir/vmlinuz-linux-cachyos" ]]; then
            echo "Copying kernel files from $esp_dir to /boot..."
            cp "$esp_dir/vmlinuz-linux-cachyos" /boot/
            cp "$esp_dir/initramfs-linux-cachyos"*.img /boot/ 2>/dev/null || true
            [[ -f "$esp_dir/amd-ucode.img" ]] && cp "$esp_dir/amd-ucode.img" /boot/
            [[ -f "$esp_dir/intel-ucode.img" ]] && cp "$esp_dir/intel-ucode.img" /boot/
            echo "✓ Kernel files copied to /boot"
            return 0
        fi
    done

    # If not found, install kernel package
    echo "Installing kernel package to populate /boot..."
    pacman -S --noconfirm linux-cachyos
    echo "✓ Kernel package installed"
}

# Function to clean up any unbootable snapshots created during install
cleanup_unbootable_snapshots() {
    echo "Checking for unbootable snapshots created during setup..."

    local root_dataset=$(findmnt -no SOURCE / 2>/dev/null || echo "")
    if [[ -z "$root_dataset" ]]; then
        echo "Could not detect root dataset, skipping cleanup"
        return 0
    fi

    # Find snapshots without kernel files (created in last hour)
    local recent_snapshots=$(zfs list -H -t snapshot -o name,creation -r "$root_dataset" 2>/dev/null | \
                            grep "@pacman-" | \
                            awk '{print $1}')

    for snapshot in $recent_snapshots; do
        # Check if this snapshot has kernel files
        # We'll mount it temporarily to check
        local temp_mount="/tmp/zfs-check-$$"
        mkdir -p "$temp_mount"

        if mount -t zfs -o ro "$snapshot" "$temp_mount" 2>/dev/null; then
            if [[ ! -f "$temp_mount/boot/vmlinuz-linux-cachyos" ]]; then
                echo "Found unbootable snapshot: $snapshot"
                umount "$temp_mount" 2>/dev/null || true

                # Destroy the unbootable snapshot
                echo "Removing unbootable snapshot: $snapshot"
                zfs destroy "$snapshot" 2>/dev/null || echo "  Failed to remove (may be in use)"
            else
                umount "$temp_mount" 2>/dev/null || true
            fi
        fi

        rmdir "$temp_mount" 2>/dev/null || true
    done

    echo "✓ Snapshot cleanup complete"
}

install_fish_config() {
    echo "Installing Fish shell configuration..."

    local fish_config_dir="$USER_HOME/.config/fish"
    sudo -u "$SUDO_USER" mkdir -p "$fish_config_dir/functions"

    # Copy fish config and functions
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/fish-shell/config.fish" "$fish_config_dir/"
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/fish-shell/functions/"*.fish "$fish_config_dir/functions/"

    echo "✓ Fish configuration installed"
}

install_system_scripts() {
    echo "Installing system scripts..."

    # Copy snapshot scripts FIRST (but don't activate hooks yet)
    cp "$SCRIPT_DIR/system-scripts/snapshot-scripts/"*.sh /usr/local/sbin/
    chmod +x /usr/local/sbin/zfs-*.sh

    # Ensure hooks directory exists
    mkdir -p /etc/pacman.d/hooks

    # Copy systemd units
    cp "$SCRIPT_DIR/system-scripts/systemd-units/"* /etc/systemd/system/
    systemctl daemon-reload

    # Copy other scripts
    cp "$SCRIPT_DIR/system-scripts/copy-kernel-to-esp.sh" /usr/local/sbin/ 2>/dev/null || true
    cp "$SCRIPT_DIR/system-scripts/zbm-sync-be-kernel.sh" /usr/local/sbin/ 2>/dev/null || true
    chmod +x /usr/local/sbin/*.sh

    echo "✓ System scripts installed (hooks not yet activated)"
}

install_pacman_hooks() {
    echo "Installing pacman hooks..."

    # NOW install the hooks after kernels are in place
    cp "$SCRIPT_DIR/system-scripts/pacman-hooks/"*.hook /etc/pacman.d/hooks/

    echo "✓ Pacman hooks installed and active"
}

enable_zfs_automation() {
    echo "Enabling ZFS automation..."

    # Enable scrub timer for main pool (assumes zpcachyos)
    systemctl enable --now zpool-scrub@zpcachyos.timer 2>/dev/null || \
        echo "  Note: zpool-scrub timer not enabled (pool may not exist yet)"

    echo "✓ ZFS automation enabled"
    echo "  - Monthly pool scrubs: systemctl status zpool-scrub@zpcachyos.timer"
    echo "  - Pacman snapshot hooks: ls /etc/pacman.d/hooks/*zfs*"
}

set_fish_default() {
    echo "Setting Fish as default shell..."

    if [[ "$SUDO_USER" != "root" ]] && ! grep -q "/usr/bin/fish" /etc/passwd | grep "$SUDO_USER"; then
        chsh -s /usr/bin/fish "$SUDO_USER"
        echo "✓ Fish set as default shell for $SUDO_USER"
    else
        echo "✓ Fish already default or user is root"
    fi
}

detect_setup_stage() {
    # Detect if we're in initial setup or post-ZBM setup
    if [[ -f /etc/zfsbootmenu/config.yaml ]]; then
        echo "detected"
        return 0
    else
        echo "not-detected"
        return 1
    fi
}


install_embedded_pacman_hooks() {
  echo "Installing embedded pacman hooks and helper scripts..."

  install -d /etc/pacman.d/hooks
  install -d /usr/local/sbin

  # --- Helper: pre-transaction snapshot (skips if BE not bootable) ---
  cat >/usr/local/sbin/zfs-pre-pacman-snapshot.sh <<'H_SH'
#!/usr/bin/env bash
set -euo pipefail
POOL=$(zpool list -H -o name | head -n1)
BOOTFS=$(zpool get -H -o value bootfs "$POOL")
MNT=$(mktemp -d)
trap 'umount -lf "$MNT" >/dev/null 2>&1 || true; rmdir "$MNT" >/dev/null 2>&1 || true' EXIT

# Try to mount; OK if already mounted elsewhere
mount -t zfs "$BOOTFS" "$MNT" >/dev/null 2>&1 || true

shopt -s nullglob
kernels=( "$MNT"/boot/vmlinuz* "$MNT"/boot/linux* "$MNT"/boot/Image* )
inits=( "$MNT"/boot/initramfs-* "$MNT"/boot/initrd-* )
ukis=( "$MNT"/boot/*.efi )
shopt -u nullglob

if (( ${#ukis[@]} > 0 )) || (( ${#kernels[@]} > 0 && ${#inits[@]} > 0 )); then
  ts=$(date +%Y%m%d-%H%M%S)
  zfs snapshot "${BOOTFS}@pacman-${ts}"
else
  echo "[zfs-pre-pacman-snapshot] Skipping: BE lacks kernel assets" >&2
fi
H_SH
  chmod 0755 /usr/local/sbin/zfs-pre-pacman-snapshot.sh

  # --- Helper: prune old pacman snapshots (keep last 20) ---
  cat >/usr/local/sbin/zfs-prune-pacman-snapshots.sh <<'H_SH'
#!/usr/bin/env bash
set -euo pipefail
KEEP=${KEEP:-20}
POOL=$(zpool list -H -o name | head -n1)
BOOTFS=$(zpool get -H -o value bootfs "$POOL")
mapfile -t snaps < <(zfs list -H -t snapshot -o name -s creation | grep "^${BOOTFS}@pacman-")
if (( ${#snaps[@]} > KEEP )); then
  del_count=$(( ${#snaps[@]} - KEEP ))
  printf "%s\n" "${snaps[@]:0:del_count}" | xargs -r -n1 zfs destroy
fi
H_SH
  chmod 0755 /usr/local/sbin/zfs-prune-pacman-snapshots.sh

  # --- Optional helper: copy kernel/initramfs to ESP (fallback) ---
  if [[ "${USE_SYSTEMD_BOOT_FALLBACK:-true}" == "true" ]]; then
    cat >/usr/local/sbin/copy-kernel-to-esp.sh <<'H_SH'
#!/usr/bin/env bash
set -euo pipefail
ESP="${ESP:-/efi}"
if [[ ! -d "$ESP" ]]; then
  if mountpoint -q /boot/efi; then ESP=/boot/efi; else
    echo "[copy-kernel-to-esp] ESP not mounted at /efi or /boot/efi; skipping" >&2
    exit 0
  fi
fi
mkdir -p "$ESP/EFI/Linux"
shopt -s nullglob
bootsrc=( /boot/vmlinuz* /boot/linux* /boot/Image* )
initsrc=( /boot/initramfs-* /boot/initrd-* )
ukisrc=( /boot/*.efi )
shopt -u nullglob
if (( ${#ukisrc[@]} > 0 )); then
  cp -f "${ukisrc[@]}" "$ESP/EFI/Linux/"
elif (( ${#bootsrc[@]} > 0 && ${#initsrc[@]} > 0 )); then
  cp -f "${bootsrc[@]}" "${initsrc[@]}" "$ESP/EFI/Linux/"
else
  echo "[copy-kernel-to-esp] No kernel assets in /boot; skipping" >&2
fi
H_SH
    chmod 0755 /usr/local/sbin/copy-kernel-to-esp.sh
  fi

  # --- Hooks ---
  cat >/etc/pacman.d/hooks/00-zfs-pre-snapshot.hook <<'H_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = ZFS snapshot of root BE (pre-transaction, only if bootable)
When = PreTransaction
Exec = /usr/local/sbin/zfs-pre-pacman-snapshot.sh
H_HOOK

  cat >/etc/pacman.d/hooks/99-zfs-prune-snapshots.hook <<'H_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Prune old ZFS pacman snapshots (keep last 20)
When = PostTransaction
Exec = /usr/local/sbin/zfs-prune-pacman-snapshots.sh
H_HOOK

  cat >/etc/pacman.d/hooks/90-generate-zbm.hook <<'H_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux*
Target = mkinitcpio
Target = dracut
Target = zfsbootmenu

[Action]
Description = Generate ZFSBootMenu EFI images
When = PostTransaction
Exec = /usr/bin/bash -lc 'command -v generate-zbm >/dev/null 2>&1 && generate-zbm || true'
H_HOOK

  if [[ "${USE_SYSTEMD_BOOT_FALLBACK:-true}" == "true" ]]; then
    cat >/etc/pacman.d/hooks/10-copy-kernel-to-esp.hook <<'H_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux*
Target = mkinitcpio
Target = dracut

[Action]
Description = Mirror kernel/initramfs to ESP (fallback for firmware boot)
When = PostTransaction
Exec = /usr/local/sbin/copy-kernel-to-esp.sh
H_HOOK
  fi

  echo "✓ Pacman hooks installed (embedded)"
}

fi

    echo ""
    echo "=== Installation $([ "$zbm_configured" == "detected" ] && echo "Complete" || echo "Partially Complete") ==="
    echo ""

    if [[ "$zbm_configured" == "detected" ]]; then
        echo "Next steps:"
        echo "1. Log out and back in (or run 'exec fish') to use new shell"
        echo "2. Test ZFS functions: 'zfs-config-show'"
        echo "3. Check automation: 'systemctl list-timers | grep scrub'"
    else
        echo "Next steps:"
        echo "1. Run ZBM setup: sudo ./system-scripts/zbm-setup.sh /dev/your-esp-device"
        echo "2. Reboot and verify ZFSBootMenu shows your BE and snapshots"
        echo "3. Log out and back in to use Fish shell"
    fi
}

main "$@"
