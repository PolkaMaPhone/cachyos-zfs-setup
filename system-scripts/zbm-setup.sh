#!/usr/bin/env bash
# zbm-setup.sh v3.0 — Streamlined ZFSBootMenu setup for CachyOS/Arch
# Optimized with simplified configuration and cleaner logic

set -euo pipefail

# Configuration defaults
: "${POOL:=zpcachyos}"
: "${BE_DATASET:=zpcachyos/ROOT/cos/root}"
: "${KERNEL_BASENAME:=linux-cachyos}"
: "${ESP_DEV:=}"
: "${USE_SYSTEMD_BOOT_FALLBACK:=true}"
: "${PERSISTENT_ESP:=true}"
: "${EFI_DIR:=/efi}"
: "${ZBM_EFI_PATH:=/efi/EFI/ZBM}"
: "${ZBM_TIMEOUT:=5}"
: "${ZBM_KERNEL_CMDLINE:=rw quiet}"

# Utility functions
say() { printf "\033[1;32m[zbm-setup]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[zbm-setup]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[zbm-setup]\033[0m %s\n" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: sudo $0 /dev/nvme0n1p1
   or: sudo ESP_DEV=/dev/nvme0n1p1 $0

Configures ZFSBootMenu for your ZFS root system.
The ESP device should be your EFI System Partition (e.g., /dev/nvme0n1p1).

If the ESP is already mounted at /efi or /boot/efi, it will be auto-detected.
EOF
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root (sudo)"
}

ensure_rw_root() {
    if ! touch /tmp/.zbm-rw-test.$$ 2>/dev/null; then
        die "Root filesystem is read-only. Reboot into RW mode first."
    fi
    rm -f /tmp/.zbm-rw-test.$$
}

install_required_packages() {
    say "Checking required packages..."

    local packages=(zfsbootmenu efibootmgr dosfstools)
    local missing=()

    for pkg in "${packages[@]}"; do
        pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        say "Installing: ${missing[*]}"
        pacman -S --noconfirm "${missing[@]}" || {
            warn "Some packages failed to install from repos"
            command -v yay >/dev/null && yay -S --noconfirm "${missing[@]}"
        }
    else
        say "✓ All required packages installed"
    fi
}

detect_esp() {
    # Priority: CLI arg > env var > mounted ESP
    ESP_DEV="${1:-${ESP_DEV:-}}"

    if [[ -z "$ESP_DEV" ]]; then
        for mp in /efi /boot/efi /boot; do
            if findmnt -no FSTYPE "$mp" 2>/dev/null | grep -qx 'vfat'; then
                ESP_DEV="$(findmnt -no SOURCE "$mp")"
                say "Auto-detected ESP at $mp: $ESP_DEV"
                break
            fi
        done
    fi

    [[ -n "$ESP_DEV" ]] || { usage; die "No ESP device specified or detected"; }
    [[ -b "$ESP_DEV" ]] || die "ESP device not found: $ESP_DEV"

    say "Using ESP: $ESP_DEV"
}

ensure_dirs() {
    mkdir -p "${EFI_DIR}" "${ZBM_EFI_PATH}"
    mkdir -p /etc/zfsbootmenu/{dracut.conf.d,generate-zbm.pre.d,generate-zbm.post.d}
    mkdir -p /etc/pacman.d/hooks /etc/zfs /var/log/zfsbootmenu
}

setup_esp_mount() {
    local boot_fs="$(findmnt -no FSTYPE /boot 2>/dev/null || true)"

    # Move ESP from /boot to /efi if needed
    if [[ "$boot_fs" == "vfat" ]]; then
        say "Moving ESP from /boot to ${EFI_DIR}..."
        umount /boot || umount -l /boot
        mount -t vfat "${ESP_DEV}" "${EFI_DIR}"
    elif ! mountpoint -q "${EFI_DIR}"; then
        say "Mounting ESP at ${EFI_DIR}..."
        mount -t vfat "${ESP_DEV}" "${EFI_DIR}"
    fi

    # Persist mount if requested
    if [[ "${PERSISTENT_ESP}" == "true" ]]; then
        local uuid="$(blkid -s UUID -o value "${ESP_DEV}")"
        if ! grep -q "${uuid}.*${EFI_DIR}" /etc/fstab 2>/dev/null; then
            say "Adding ESP to /etc/fstab..."
            printf "UUID=%s  %s  vfat  umask=0077  0  2\n" "${uuid}" "${EFI_DIR}" >> /etc/fstab
        fi
    fi
}

configure_zfs_datasets() {
    say "Configuring ZFS dataset properties..."

    # Set container properties
    zfs set canmount=off mountpoint=none "${POOL}/ROOT" 2>/dev/null || true
    zfs set canmount=off mountpoint=none "${POOL}/ROOT/cos" 2>/dev/null || true

    # Configure boot environment
    local current_mp="$(zfs get -H -o value mountpoint "${BE_DATASET}" 2>/dev/null || echo "-")"
    if [[ "${current_mp}" != "/" ]]; then
        zfs set canmount=noauto mountpoint=/ "${BE_DATASET}" || \
            warn "Could not set mountpoint on live BE"
    else
        zfs set canmount=noauto "${BE_DATASET}" 2>/dev/null || true
    fi

    # Set boot filesystem
    zpool set bootfs="${BE_DATASET}" "${POOL}"

    # Set ZBM properties
    zfs set org.zfsbootmenu:rootprefix="root=ZFS=" "${POOL}/ROOT"
    zfs set org.zfsbootmenu:commandline="${ZBM_KERNEL_CMDLINE}" "${BE_DATASET}"

    say "✓ Dataset properties configured"
}

ensure_kernels() {
    local target="${1:-/boot}"
    local kernel_file="$target/vmlinuz-${KERNEL_BASENAME}"

    [[ -f "$kernel_file" ]] && return 0

    say "Installing kernel files to $target..."

    # Try copying from ESP
    if [[ -f "${EFI_DIR}/vmlinuz-${KERNEL_BASENAME}" ]]; then
        cp "${EFI_DIR}"/vmlinuz-* "${EFI_DIR}"/initramfs-* "$target/" 2>/dev/null
        cp "${EFI_DIR}"/*-ucode.img "$target/" 2>/dev/null || true
    else
        pacman -S --noconfirm "${KERNEL_BASENAME}"
    fi

    say "✓ Kernel files ready"
}

configure_mkinitcpio() {
    say "Configuring mkinitcpio for ZFS..."

    local cfg=/etc/mkinitcpio.conf

    # Add zfs hook before filesystems
    if ! grep -Eq 'HOOKS=.*\bzfs\b' "$cfg"; then
        sed -i -E 's/(HOOKS=.*) filesystems/\1 zfs filesystems/' "$cfg"
    fi

    # Generate hostid and cache file
    [[ -f /etc/hostid ]] || zgenhostid -f
    zpool set cachefile=/etc/zfs/zpool.cache "${POOL}"

    say "Rebuilding initramfs..."
    mkinitcpio -P
}

write_zbm_config() {
    say "Writing ZBM configuration..."

    cat >/etc/zfsbootmenu/config.yaml <<YAML
Global:
  ManageImages: true
  BootTimeout: ${ZBM_TIMEOUT}
  BootMountPoint: "${EFI_DIR}"

EFI:
  Enabled: true
  ImageDir: "${ZBM_EFI_PATH}"
  Versions: false
YAML

    say "✓ ZBM config written"
}

write_post_hooks() {
    say "Installing ZBM post-generation hooks..."

    # Stable filename hook
    cat >/etc/zfsbootmenu/generate-zbm.post.d/10-stable-names.sh <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

ESP_DIR="/efi/EFI/ZBM"
NEW="$(ls -1t "${ESP_DIR}"/vmlinuz-*.EFI 2>/dev/null | grep -v backup | head -n1)"

[[ -z "$NEW" ]] && exit 0

# Rotate backups
[[ -f "${ESP_DIR}/ZFSBootMenu.EFI" ]] && \
    mv -f "${ESP_DIR}/ZFSBootMenu.EFI" "${ESP_DIR}/ZFSBootMenu-backup.EFI"

# Set new stable
mv -f "$NEW" "${ESP_DIR}/ZFSBootMenu.EFI"
echo "[zbm-hook] Updated ZFSBootMenu.EFI"
HOOK
    chmod +x /etc/zfsbootmenu/generate-zbm.post.d/10-stable-names.sh

    say "✓ Post-hooks installed"
}

sync_kernels_to_esp() {
    say "Syncing kernels to ESP..."

    # Ensure kernels are in /boot first
    ensure_kernels /boot

    # Copy to ESP
    for f in /boot/vmlinuz-* /boot/initramfs-* /boot/*-ucode.img; do
        [[ -f "$f" ]] && cp -f "$f" "${EFI_DIR}/" 2>/dev/null || true
    done

    say "✓ Kernels synced to ESP"
}

generate_zbm_images() {
    say "Generating ZFSBootMenu images..."

    if generate-zbm; then
        say "✓ ZBM images generated"
        ls -lh "${ZBM_EFI_PATH}"/*.EFI 2>/dev/null || true
    else
        warn "ZBM generation had warnings - check output"
    fi
}

create_uefi_entry() {
    say "Configuring UEFI boot entry..."

    if efibootmgr | grep -q "ZFSBootMenu"; then
        say "✓ ZFSBootMenu entry already exists"
        return 0
    fi

    # Determine disk and partition
    local disk partnum
    if command -v lsblk >/dev/null && lsblk --help 2>&1 | grep -q PARTNUM; then
        disk="/dev/$(lsblk -no PKNAME "${ESP_DEV}")"
        partnum="$(lsblk -no PARTNUM "${ESP_DEV}")"
    else
        disk="${ESP_DEV%[0-9]*}"
        partnum="${ESP_DEV##*[!0-9]}"
    fi

    efibootmgr -c -d "${disk}" -p "${partnum}" \
        -L "ZFSBootMenu" -l '\EFI\ZBM\ZFSBootMenu.EFI' && \
        say "✓ Created UEFI entry: ZFSBootMenu" || \
        warn "Could not create UEFI entry - add manually"
}

final_summary() {
    say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    say "ZFSBootMenu Setup Complete!"
    say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "Configuration Summary:"
    echo "  Pool:        ${POOL}"
    echo "  Boot Dataset: ${BE_DATASET}"
    echo "  ESP:         ${ESP_DEV} → ${EFI_DIR}"
    echo "  ZBM Images:  ${ZBM_EFI_PATH}"
    echo ""

    echo "Mount Status:"
    findmnt -no FSTYPE,SOURCE,TARGET / /boot "${EFI_DIR}" 2>/dev/null | column -t
    echo ""

    echo "Kernel Locations:"
    ls -la /boot/vmlinuz-* 2>/dev/null | head -n1 || echo "  None in /boot"
    ls -la "${EFI_DIR}"/vmlinuz-* 2>/dev/null | head -n1 || echo "  None in ESP"
    echo ""

    echo "Next Steps:"
    echo "1. Reboot and select ZFSBootMenu from UEFI menu"
    echo "2. Press ESC at ZBM countdown to see boot environments"
    echo "3. Run './validate-setup.sh' to verify configuration"

    if [[ "${PERSISTENT_ESP}" != "true" ]]; then
        say "Unmounting ESP (ZBM will mount on demand)..."
        umount "${EFI_DIR}" 2>/dev/null || true
    fi
}

main() {
    require_root
    ensure_rw_root

    detect_esp "$@"
    install_required_packages
    ensure_dirs

    setup_esp_mount
    configure_zfs_datasets
    ensure_kernels /boot
    configure_mkinitcpio

    write_zbm_config
    write_post_hooks
    sync_kernels_to_esp

    generate_zbm_images
    create_uefi_entry

    final_summary
}

main "$@"
