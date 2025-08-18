#!/usr/bin/env bash
# zbm-setup.sh v1.1 — Safer, idempotent ZFSBootMenu setup for CachyOS/Arch.
# Fixes: robust ESP detection (no tree glyphs), skip mountpoint change when BE is /,
# and preflight RW root FS so we don't try to write on a RO system.

usage() {
  cat <<EOF
Usage: sudo ESP_DEV=/dev/nvme0n1p1 $0
   or:  sudo $0 /dev/nvme0n1p1

Notes:
- If the ESP is already mounted at /efi or /boot as vfat, the script will use that.
- Otherwise you MUST specify the ESP device explicitly.
EOF
}

set -euo pipefail

# ── TUNABLES (override by exporting before running) ──────────────────────────
: "${POOL:=zpcachyos}"
: "${BE_DATASET:=zpcachyos/ROOT/cos/root}"
: "${KERNEL_BASENAME:=linux-cachyos}"
: "${ESP_DEV:=}"                      # e.g. /dev/nvme0n1p1 (supply via args if empty)
: "${USE_SYSTEMD_BOOT_FALLBACK:=true}"
: "${PERSISTENT_ESP:=true}"
: "${EFI_DIR:=/efi}"
: "${ZBM_EFI_PATH:=/efi/EFI/ZBM}"
: "${ZBM_TIMEOUT:=5}"
: "${ZBM_KERNEL_CMDLINE:=rw quiet}"
# ─────────────────────────────────────────────────────────────────────────────

say() { printf "\033[1;32m[zbm-setup]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[zbm-setup]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[zbm-setup]\033[0m %s\n" "$*" >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || die "Run as root (sudo)."; }

ensure_rw_root() {
  # Bail out early if / is read-only; doing writes would just fail noisily later.
  if ! touch /tmp/.zbm-rw-test.$$ 2>/dev/null; then
    die "Root filesystem is read-only. Reboot via systemd-boot so / is RW, then rerun."
  fi
  rm -f /tmp/.zbm-rw-test.$$
}

install_required_packages() {
  say "Installing required packages..."

  local packages=(
    "zfsbootmenu"
    "efibootmgr"
    "dosfstools"
  )

  for pkg in "${packages[@]}"; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      say "Installing $pkg..."
      pacman -S --noconfirm "$pkg" || {
        warn "Failed to install $pkg from official repos, trying AUR..."
        if command -v yay >/dev/null; then
          yay -S --noconfirm "$pkg"
        else
          die "Package $pkg not found and no AUR helper available"
        fi
      }
    fi
  done
}

detect_esp() {
  # Priority 1: CLI arg
  if [[ $# -ge 1 && -n "${1:-}" ]]; then
    ESP_DEV="$1"
    say "ESP provided via argument: ${ESP_DEV}"
    return 0
  fi
  # Priority 2: env var
  if [[ -n "${ESP_DEV}" ]]; then
    say "ESP provided via ENV: ${ESP_DEV}"
    return 0
  fi
  # Priority 3: already-mounted vfat at /efi or /boot
  for mp in /efi /boot; do
    if findmnt -no FSTYPE "$mp" 2>/dev/null | grep -qx 'vfat'; then
      ESP_DEV="$(findmnt -no SOURCE "$mp")"
      say "Found mounted ESP at ${mp}: ${ESP_DEV}"
      return 0
    fi
  done
  # Otherwise: bail
  usage
  die "No ESP specified and none mounted at /efi or /boot"
}

ensure_dirs() {
  mkdir -p "${EFI_DIR}" "${ZBM_EFI_PATH}"
  mkdir -p /etc/zfsbootmenu/{dracut.conf.d,generate-zbm.pre.d,generate-zbm.post.d}
  mkdir -p /etc/pacman.d/hooks /etc/zfs
}

move_esp_to_efi_if_needed() {
  # Goal: /boot is a dir on ZFS; ESP is not mounted on /boot.
  local boot_fs

  if findmnt -no SOURCE /efi 2>/dev/null | grep -q "$ESP_DEV"; then
    say "ESP already mounted at /efi, no move needed"
    return 0
  fi

  boot_fs="$(findmnt -no FSTYPE /boot || true)"
  if [[ "$boot_fs" == "vfat" ]]; then
    say "ESP currently at /boot; moving it to ${EFI_DIR}…"
    umount /boot || { warn "Forcing lazy unmount of /boot"; umount -l /boot; }
    mount -t vfat "${ESP_DEV}" "${EFI_DIR}"
  else
    # Ensure ESP is mounted for initial writes (we may unmount later)
    if ! mountpoint -q "${EFI_DIR}"; then
      say "Temporarily mounting ESP at ${EFI_DIR}…"
      mount -t vfat "${ESP_DEV}" "${EFI_DIR}"
    fi
  fi
}

maybe_persist_esp_mount() {
  if [[ "${PERSISTENT_ESP}" == "true" ]]; then
    say "Persisting ESP mount in /etc/fstab at ${EFI_DIR}…"
    local uuid
    uuid="$(blkid -s UUID -o value "${ESP_DEV}")"
    grep -q "${uuid}.*${EFI_DIR}" /etc/fstab 2>/dev/null || \
      printf "UUID=%s  %s  vfat  umask=0077  0  2\n" "${uuid}" "${EFI_DIR}" >> /etc/fstab
  else
    say "Not persisting ESP in fstab (ZBM mounts it on demand)."
  fi
}

set_dataset_layout() {
  say "Setting dataset mount policies (skipping BE mountpoint change if BE is /)…"
  zfs set canmount=off    "${POOL}/ROOT"       || true
  zfs set mountpoint=none "${POOL}/ROOT"       || true
  zfs set canmount=off    "${POOL}/ROOT/cos"   || true
  zfs set mountpoint=none "${POOL}/ROOT/cos"   || true

  # Only tweak BE if it doesn't already mount at /
  local current_mp
  current_mp="$(zfs get -H -o value mountpoint "${BE_DATASET}" 2>/dev/null || echo "-")"
  if [[ "${current_mp}" != "/" ]]; then
    zfs set canmount=noauto "${BE_DATASET}"
    zfs set mountpoint=/    "${BE_DATASET}" || warn "BE is live at /; mountpoint left unchanged."
  else
    zfs set canmount=noauto "${BE_DATASET}" || true
    say "BE already mounted at /; leaving mountpoint as-is."
  fi
  zpool set bootfs="${BE_DATASET}" "${POOL}"
}

prune_child_cmdline_props() {
  local base="${POOL}/ROOT"
  # Remove property from all children except the root BE
  mapfile -t kids < <(zfs list -H -o name -r "$base" | grep -v "^${base}$")
  for ds in "${kids[@]}"; do
    # Only clear if set
    if zfs get -H -o value org.zfsbootmenu:commandline "$ds" 2>/dev/null | grep -qv '-' ; then
      zfs inherit -S org.zfsbootmenu:commandline "$ds" || true
    fi
  done

  # Set a clean inheritable default on $POOL/ROOT
  zfs set org.zfsbootmenu:commandline="${ZBM_KERNEL_CMDLINE:-rw quiet}" "$base"
}


set_zbm_dataset_properties() {
  say "Setting ZBM dataset properties..."
  "${ZBM_KERNEL_CMDLINE:=quiet loglevel=0 nowatchdog}"
  # Set once at ROOT; BEs inherit (can override per-BE when needed)
  zfs set org.zfsbootmenu:commandline="${ZBM_KERNEL_CMDLINE}" "${POOL}/ROOT"

  say "ZBM dataset properties configured"
}

ensure_kernel_files_in_boot() {
  say "Ensuring kernel files are available in /boot for mkinitcpio..."

  # Make sure /boot directory exists
  mkdir -p /boot

  local kernel_file="/boot/vmlinuz-${KERNEL_BASENAME}"
  local initramfs_file="/boot/initramfs-${KERNEL_BASENAME}.img"
  local fallback_file="/boot/initramfs-${KERNEL_BASENAME}-fallback.img"

  # Check if kernel files are missing from /boot
  if [[ ! -f "$kernel_file" ]]; then
    say "Kernel files missing from /boot, checking for sources..."

    # Option 1: Copy from ESP if they exist there
    if [[ -f "${EFI_DIR}/vmlinuz-${KERNEL_BASENAME}" ]]; then
      say "Copying kernel files from ESP to /boot..."
      cp "${EFI_DIR}/vmlinuz-${KERNEL_BASENAME}" /boot/
      cp "${EFI_DIR}/initramfs-${KERNEL_BASENAME}"* /boot/ 2>/dev/null || true
    # Option 2: Reinstall kernel package to populate /boot
    elif pacman -Q "${KERNEL_BASENAME}" >/dev/null 2>&1; then
      say "Kernel package installed but files missing, reinstalling..."
      pacman -S --noconfirm "${KERNEL_BASENAME}"
    # Option 3: Install kernel package if not present
    else
      say "Installing kernel package: ${KERNEL_BASENAME}..."
      pacman -S --noconfirm "${KERNEL_BASENAME}"
    fi
  else
    say "Kernel files already present in /boot"
  fi

  # Verify kernel files are now available
  if [[ ! -f "$kernel_file" ]]; then
    die "Failed to ensure kernel files in /boot. Manual intervention required."
  fi

  say "✓ Kernel files ready in /boot for mkinitcpio"
}

ensure_mkinitcpio_has_zfs() {
  say "Ensuring mkinitcpio HOOKS includes 'zfs' before 'filesystems'…"
  local cfg=/etc/mkinitcpio.conf
  [[ -w "$cfg" ]] || die "Cannot write ${cfg} (root may be RO)."
  if ! grep -Eq 'HOOKS=.*\bzfs\b' "$cfg"; then
    sed -i -E 's/(HOOKS=.*) filesystems/\1 zfs filesystems/' "$cfg"
  else
    # Ensure ordering: zfs before filesystems; otherwise leave user's list intact.
    grep -Eq 'HOOKS=.*zfs.*filesystems' "$cfg" || \
      sed -i -E 's/(HOOKS=.*) filesystems/\1 zfs filesystems/' "$cfg"
  fi

  say "Ensuring /etc/hostid and /etc/zfs/zpool.cache exist for early import…"
  [[ -f /etc/hostid ]] || zgenhostid -f
  zpool set cachefile=/etc/zfs/zpool.cache "${POOL}"

  say "Rebuilding initramfs for ${KERNEL_BASENAME}…"
  # Sanity: /boot must be writable now that it's on ZFS
  [[ -w /boot ]] || die "/boot is not writable; is it still mounted as ESP? (Should be a ZFS dir)"
  mkinitcpio -P
}

install_pacman_snapshot_hooks() {
  # pre-snapshot helper
  install -D -m 0755 /dev/stdin /usr/local/sbin/zfs-pre-pacman-snapshot.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
POOL=$(zpool list -H -o name | head -n1)
BOOTFS=$(zpool get -H -o value bootfs "$POOL")
ts=$(date +%Y%m%d-%H%M%S)
zfs snapshot "${BOOTFS}@pacman-${ts}"
SH

  # prune helper (keep last 20)
  install -D -m 0755 /dev/stdin /usr/local/sbin/zfs-prune-pacman-snapshots.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
KEEP=${KEEP:-20}
POOL=$(zpool list -H -o name | head -n1)
BOOTFS=$(zpool get -H -o value bootfs "$POOL")
zfs list -H -t snapshot -o name -s creation | grep "^${BOOTFS}@pacman-" | head -n -${KEEP} | xargs -r -n1 zfs destroy
SH

  # hooks
  install -D -m 0644 /dev/stdin /etc/pacman.d/hooks/00-zfs-pre-snapshot.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *
[Action]
Description = ZFS snapshot of root BE (pre-transaction)
When = PreTransaction
Exec = /usr/bin/env BATCH_WINDOW=5 /usr/local/sbin/zfs-pre-pacman-snapshot.sh
HOOK

  install -D -m 0644 /dev/stdin /etc/pacman.d/hooks/99-zfs-prune-snapshots.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *
[Action]
Description = Prune old ZFS pacman snapshots (keep last 20)
When = PostTransaction
Exec = /usr/bin/env KEEP=20 /usr/local/sbin/zfs-prune-pacman-snapshots.sh
HOOK
}


write_zbm_config() {
  say "Writing /etc/zfsbootmenu/config.yaml…"
  cat >/etc/zfsbootmenu/config.yaml <<YAML
Global:
  ManageImages: true
  BootTimeout: ${ZBM_TIMEOUT} #seconds
  BootMountPoint: "${EFI_DIR}"
  RootPrefix: "root=ZFS="
  KernelCmdline: "${ZBM_KERNEL_CMDLINE}"
  DracutConfDir: /etc/zfsbootmenu/dracut.conf.d
  PreHooksDir: /etc/zfsbootmenu/generate-zbm.pre.d
  PostHooksDir: /etc/zfsbootmenu/generate-zbm.post.d
  InitCPIOConfig: /etc/zfsbootmenu/mkinitcpio.conf

EFI:
  Enabled: true
  ImageDir: "${ZBM_EFI_PATH}"
  Versions: false

Components:
  Enabled: false
YAML
}

write_post_hook_rename() {
  say "Writing post-hook to create stable UKI filenames for firmware entry…"
  cat >/etc/zfsbootmenu/generate-zbm.post.d/10-rename-uki.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
ESP_DIR="/efi/EFI/ZBM"
LOG="/var/log/zfsbootmenu/uki-rename.log"
mkdir -p "$(dirname "$LOG")" || true
ts(){ date '+%F %T'; }
log(){ echo "[$(ts)] $*" | tee -a "$LOG" >&2; }

# Newest non-backup UKI (any kernel flavor)
NEW_MAIN="$(ls -1t "${ESP_DIR}"/vmlinuz-*.EFI 2>/dev/null | grep -v -- '-backup\.EFI$' | head -n1 || true)"
if [[ -z "$NEW_MAIN" ]]; then
  log "No vmlinuz-*.EFI found in ${ESP_DIR}; nothing to do."
  exit 0
fi

base="${NEW_MAIN%.EFI}"
BUILDER_BKP="${base}-backup.EFI"

# Prefer the builder's matching backup as fallback; else preserve current stable
if [[ -f "$BUILDER_BKP" ]]; then
  log "Using builder backup $(basename "$BUILDER_BKP") -> ZFSBootMenu-fallback.EFI"
  mv -f "$BUILDER_BKP" "${ESP_DIR}/ZFSBootMenu-fallback.EFI"
elif [[ -f "${ESP_DIR}/ZFSBootMenu.EFI" ]]; then
  log "No builder backup; preserving current ZFSBootMenu.EFI -> ZFSBootMenu-fallback.EFI"
  mv -f "${ESP_DIR}/ZFSBootMenu.EFI" "${ESP_DIR}/ZFSBootMenu-fallback.EFI"
else
  log "No builder backup and no existing stable; fallback unchanged."
fi

log "Setting new stable: $(basename "$NEW_MAIN") -> ZFSBootMenu.EFI"
mv -f "$NEW_MAIN" "${ESP_DIR}/ZFSBootMenu.EFI"
SH
  chmod +x /etc/zfsbootmenu/generate-zbm.post.d/10-rename-uki.sh
}

write_post_hook_ensure_kernels() {
  say "Writing post-hook to ensure all BEs have kernel files..."
  cat >/etc/zfsbootmenu/generate-zbm.post.d/20-ensure-be-kernels.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/zfsbootmenu/kernel-ensure.log"
mkdir -p "$(dirname "$LOG")" || true
ts(){ date '+%F %T'; }
log(){ echo "[$(ts)] $*" | tee -a "$LOG" >&2; }

# Find all boot environments that need kernel files
while IFS= read -r be_root; do
    be_name=$(basename $(dirname "$be_root"))

    # Skip if it's the current running BE
    [[ "$be_root" == "$(findmnt -no SOURCE /)" ]] && continue

    # Mount BE and check for kernels
    temp_mount="/mnt/zbm-kernel-check-$$"
    mkdir -p "$temp_mount"

    if mount -t zfs "$be_root" "$temp_mount" 2>/dev/null; then
        if [[ ! -f "$temp_mount/boot/vmlinuz-linux-cachyos" ]]; then
            log "Adding kernel files to BE: $be_name"
            mkdir -p "$temp_mount/boot"
            cp /boot/* "$temp_mount/boot/" 2>/dev/null || true
            log "✓ Kernel files added to $be_name"
        fi
        umount "$temp_mount"
    else
        log "Failed to mount $be_root for kernel check"
    fi

    rmdir "$temp_mount" 2>/dev/null || true
done < <(zfs list -H -o name -r zpcachyos/ROOT 2>/dev/null | grep "/root$" || true)

log "Kernel file check complete"
SH
  chmod +x /etc/zfsbootmenu/generate-zbm.post.d/20-ensure-be-kernels.sh
}

write_generate_zbm_hook() {
  say "Installing pacman hook to rebuild ZBM after kernel updates…"
  cat >/etc/pacman.d/hooks/90-generate-zbm.hook <<HOOK
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = ${KERNEL_BASENAME}

[Action]
When = PostTransaction
Exec = /usr/bin/generate-zbm
Description = Rebuild ZFSBootMenu UKI after ${KERNEL_BASENAME} updates
HOOK
}

write_copy_to_esp_bits_if_enabled() {
  if [[ "${USE_SYSTEMD_BOOT_FALLBACK}" == "true" ]]; then
    say "Adding helper + hook to mirror kernel/initramfs to ESP for systemd-boot fallback…"
    cat >/usr/local/sbin/copy-kernel-to-esp.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
ESP=${ESP:-/efi}               # override if you like
ESP_DEV=${ESP_DEV:-}           # e.g. /dev/nvme0n1p1 to allow mounting
K=/boot/vmlinuz-linux-cachyos
I=/boot/initramfs-linux-cachyos.img

mkdir -p "$ESP"
mounted_before=false

# Mount on demand only if ESP_DEV is set and not already mounted
if ! findmnt -no FSTYPE "$ESP" 2>/dev/null | grep -qx 'vfat'; then
  if [[ -n "$ESP_DEV" ]]; then
    echo "[copy-kernel-to-esp] Mounting $ESP_DEV at $ESP"
    mount -t vfat "$ESP_DEV" "$ESP" || { echo "[copy-kernel-to-esp] mount failed; skipping"; exit 0; }
    mounted_before=true
  else
    echo "[copy-kernel-to-esp] $ESP not mounted and ESP_DEV not set; skipping."
    exit 0
  fi
fi

[[ -f "$K" ]] && install -m0644 "$K" "$ESP/"
[[ -f "$I" ]] && install -m0644 "$I" "$ESP/"
[[ -f /boot/amd-ucode.img   ]] && install -m0644 /boot/amd-ucode.img   "$ESP/"
[[ -f /boot/intel-ucode.img ]] && install -m0644 /boot/intel-ucode.img "$ESP/"

$mounted_before && umount "$ESP" || true
exit 0
SH
    chmod +x /usr/local/sbin/copy-kernel-to-esp.sh
    cat >/etc/pacman.d/hooks/10-copy-kernel-to-esp.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux-cachyos

[Action]
When = PostTransaction
# provide your ESP device explicitly:
Exec = /usr/bin/env ESP_DEV=/dev/nvme0n1p1 /usr/local/sbin/copy-kernel-to-esp.sh
Description = Mirror kernel/initramfs to ESP for systemd-boot fallback
HOOK
  else
    warn "Skipping systemd-boot fallback hook (USE_SYSTEMD_BOOT_FALLBACK=false)."
  fi
}

generate_zbm_images() {
  say "Generating ZBM UKIs…"
  generate-zbm -d
  ls -lh "${ZBM_EFI_PATH}" || true
}

create_uefi_entry_if_missing() {
  say "Ensuring UEFI boot entry exists…"
  if efibootmgr -v | grep -qi "ZFSBootMenu"; then
    say "ZFSBootMenu NVRAM entry already present."
  else
    local disk partnum

    # More robust partition number detection
    if command -v lsblk >/dev/null && lsblk --help 2>&1 | grep -q PARTNUM; then
      # New lsblk with PARTNUM support
      disk="/dev/$(lsblk -no PKNAME "${ESP_DEV}")"
      partnum="$(lsblk -no PARTNUM "${ESP_DEV}")"
    else
      # Fallback: extract partition number from device name
      disk="${ESP_DEV%[0-9]*}"  # Remove trailing numbers
      partnum="${ESP_DEV##*[!0-9]}"  # Extract trailing numbers
    fi

    efibootmgr -c -d "${disk}" -p "${partnum}" \
      -L "ZFSBootMenu" -l '\EFI\ZBM\ZFSBootMenu.EFI'
    say "Created UEFI entry: ZFSBootMenu"
  fi
}
ensure_kernel_files_synced() {
  say "Ensuring kernel files are synced between /boot and ESP..."

  # Make sure /boot directory exists on ZFS
  mkdir -p /boot

  local kernel_file="/boot/vmlinuz-${KERNEL_BASENAME}"
  local initramfs_file="/boot/initramfs-${KERNEL_BASENAME}.img"

  # If /boot is missing files, get them from ESP or package
  if [[ ! -f "$kernel_file" ]]; then
    if [[ -f "${EFI_DIR}/vmlinuz-${KERNEL_BASENAME}" ]]; then
      say "Copying kernel files from ESP to /boot..."
      install -m0644 "${EFI_DIR}/vmlinuz-${KERNEL_BASENAME}" /boot/
      install -m0644 "${EFI_DIR}/initramfs-${KERNEL_BASENAME}.img" /boot/
      [[ -f "${EFI_DIR}/amd-ucode.img" ]] && install -m0644 "${EFI_DIR}/amd-ucode.img" /boot/
      [[ -f "${EFI_DIR}/intel-ucode.img" ]] && install -m0644 "${EFI_DIR}/intel-ucode.img" /boot/
    else
      say "Installing kernel package to populate /boot..."
      pacman -S --noconfirm "${KERNEL_BASENAME}"
    fi
  fi

  # Sync /boot files to ESP (for systemd-boot fallback)
  if [[ -f "$kernel_file" ]]; then
    say "Syncing kernel files from /boot to ESP..."
    install -m0644 /boot/vmlinuz-* "${EFI_DIR}/"
    install -m0644 /boot/initramfs-* "${EFI_DIR}/"
    [[ -f /boot/amd-ucode.img ]] && install -m0644 /boot/amd-ucode.img "${EFI_DIR}/"
    [[ -f /boot/intel-ucode.img ]] && install -m0644 /boot/intel-ucode.img "${EFI_DIR}/"
  fi

  say "✓ Kernel files synced"
}

verify_be_boot_assets() {
  local ds="$1"
  local mnt
  mnt="$(mktemp -d)"
  mount -t zfs "$ds" "$mnt"
  if ! (ls "$mnt/boot" | grep -Eq '(^vmlinuz|^linux|^Image|\.efi$)' && \
        ls "$mnt/boot" | grep -Eq '(^initramfs-|^initrd-|\.efi$)'); then
    umount "$mnt"; rmdir "$mnt"
    die "BE $ds lacks kernel/initramfs in /boot"
  fi
  umount "$mnt"; rmdir "$mnt"
}


final_checks() {
  say "Quick status:"
  findmnt -no FSTYPE,SOURCE,TARGET /
  findmnt -no FSTYPE,SOURCE,TARGET /boot || true
  findmnt -no FSTYPE,SOURCE,TARGET "${EFI_DIR}" || true
  zpool get bootfs "${POOL}"
  echo "ZBM args will use: root=ZFS=${BE_DATASET}"
}

main() {
  require_root
  ensure_rw_root
  install_required_packages
  detect_esp "$@"
  ensure_dirs
  move_esp_to_efi_if_needed
  maybe_persist_esp_mount
  set_dataset_layout
  prune_child_cmdline_props
  set_zbm_dataset_properties
  ensure_kernel_files_in_boot
  ensure_mkinitcpio_has_zfs
  install_pacman_snapshot_hooks
  write_zbm_config
  write_post_hook_rename
  write_post_hook_ensure_kernels
  write_generate_zbm_hook
  write_copy_to_esp_bits_if_enabled
  generate_zbm_images
  create_uefi_entry_if_missing
  ensure_kernel_files_synced
  verify_be_boot_assets
  final_checks
  if [[ "${PERSISTENT_ESP}" != "true" ]]; then
    say "Un-mounting ESP (ZBM will mount it on demand)…"
    umount "${EFI_DIR}" || true
  fi
  say "Done. Reboot and try ZFSBootMenu when ready."
}

main "$@"
