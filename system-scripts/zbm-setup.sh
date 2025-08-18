#!/usr/bin/env bash
# zbm-setup.sh v2.0 — Fixed kernel discovery for cloned BEs
# Key fixes:
# 1. Ensures /boot is always on the root dataset (not ESP)
# 2. Configures ZBM to use a shared kernel from ESP
# 3. Sets up dracut to find kernels properly

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hooks-common.sh"

say() { printf "\033[1;32m[zbm-setup]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[zbm-setup]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[zbm-setup]\033[0m %s\n" "$*" >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || die "Run as root (sudo)."; }

ensure_rw_root() {
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
    # Ensure ESP is mounted for initial writes
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
  say "Setting dataset mount policies..."
  zfs set canmount=off    "${POOL}/ROOT"       || true
  zfs set mountpoint=none "${POOL}/ROOT"       || true
  zfs set canmount=off    "${POOL}/ROOT/cos"   || true
  zfs set mountpoint=none "${POOL}/ROOT/cos"   || true

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

set_zbm_dataset_properties() {
  say "Setting ZBM dataset properties..."

  # Set root prefix on the BE root container
  zfs set org.zfsbootmenu:rootprefix="root=ZFS=" "${POOL}/ROOT"

  # Set command line on the specific boot environment
  zfs set org.zfsbootmenu:commandline="${ZBM_KERNEL_CMDLINE}" "${BE_DATASET}"

  # CRITICAL: Tell ZBM to look for kernels on ESP, not in each BE
  # This allows cloned BEs to work without copying kernels
  zfs set org.zfsbootmenu:kernelpath="/efi" "${POOL}/ROOT"

  say "ZBM dataset properties configured"
}

ensure_kernel_files_in_boot() {
  say "Ensuring kernel files are in /boot on root dataset..."

  # Make sure /boot directory exists on the root dataset
  mkdir -p /boot

  local kernel_file="/boot/vmlinuz-${KERNEL_BASENAME}"

  if [[ ! -f "$kernel_file" ]]; then
    say "Kernel files missing from /boot, installing..."

    # Copy from ESP if they exist there
    if [[ -f "${EFI_DIR}/vmlinuz-${KERNEL_BASENAME}" ]]; then
      say "Copying kernel files from ESP to /boot..."
      cp "${EFI_DIR}/vmlinuz-${KERNEL_BASENAME}" /boot/
      cp "${EFI_DIR}/initramfs-${KERNEL_BASENAME}"* /boot/ 2>/dev/null || true
      [[ -f "${EFI_DIR}/amd-ucode.img" ]] && cp "${EFI_DIR}/amd-ucode.img" /boot/
      [[ -f "${EFI_DIR}/intel-ucode.img" ]] && cp "${EFI_DIR}/intel-ucode.img" /boot/
    else
      # Reinstall kernel package to populate /boot
      say "Installing kernel package: ${KERNEL_BASENAME}..."
      pacman -S --noconfirm "${KERNEL_BASENAME}"
    fi
  fi

  say "✓ Kernel files ready in /boot"
}

ensure_mkinitcpio_has_zfs() {
  say "Ensuring mkinitcpio HOOKS includes 'zfs' before 'filesystems'…"
  local cfg=/etc/mkinitcpio.conf
  [[ -w "$cfg" ]] || die "Cannot write ${cfg} (root may be RO)."

  if ! grep -Eq 'HOOKS=.*\bzfs\b' "$cfg"; then
    sed -i -E 's/(HOOKS=.*) filesystems/\1 zfs filesystems/' "$cfg"
  else
    grep -Eq 'HOOKS=.*zfs.*filesystems' "$cfg" || \
      sed -i -E 's/(HOOKS=.*) filesystems/\1 zfs filesystems/' "$cfg"
  fi

  say "Ensuring /etc/hostid and /etc/zfs/zpool.cache exist for early import…"
  [[ -f /etc/hostid ]] || zgenhostid -f
  zpool set cachefile=/etc/zfs/zpool.cache "${POOL}"

  say "Rebuilding initramfs for ${KERNEL_BASENAME}…"
  mkinitcpio -P
}

write_zbm_config() {
  say "Writing /etc/zfsbootmenu/config.yaml…"
  cat >/etc/zfsbootmenu/config.yaml <<YAML
Global:
  ManageImages: true
  BootTimeout: ${ZBM_TIMEOUT}
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

Kernel:
  # Tell ZBM to use kernel from ESP instead of searching BEs
  Path: "${EFI_DIR}/vmlinuz-${KERNEL_BASENAME}"
  Initramfs: "${EFI_DIR}/initramfs-${KERNEL_BASENAME}.img"
YAML
}

write_dracut_conf() {
  say "Writing dracut configuration for ZBM kernel discovery..."

  # This tells dracut/ZBM where to find kernels for ALL boot environments
  cat >/etc/zfsbootmenu/dracut.conf.d/10-kernel-path.conf <<EOF
# Tell ZBM to use kernels from ESP for all BEs
kernel_cmdline="root=ZFS=${BE_DATASET} ${ZBM_KERNEL_CMDLINE}"
uefi_stub="/usr/lib/systemd/boot/efi/linuxx64.efi.stub"

# Use ESP kernels for all BE boots
install_items+=" ${EFI_DIR}/vmlinuz-${KERNEL_BASENAME} "
install_items+=" ${EFI_DIR}/initramfs-${KERNEL_BASENAME}.img "
EOF

  # Additional config to help with BE discovery
  cat >/etc/zfsbootmenu/dracut.conf.d/20-zfs-be.conf <<EOF
# Ensure ZBM can find and boot all BEs regardless of kernel location
omit_dracutmodules+=" btrfs resume "
add_dracutmodules+=" zfs zfsbootmenu "
EOF
}

write_post_hook_rename() {
  say "Writing post-hook to create stable UKI filenames..."
  cat >/etc/zfsbootmenu/generate-zbm.post.d/10-rename-uki.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
ESP_DIR="/efi/EFI/ZBM"
LOG="/var/log/zfsbootmenu/uki-rename.log"
mkdir -p "$(dirname "$LOG")" || true
ts(){ date '+%F %T'; }
log(){ echo "[$(ts)] $*" | tee -a "$LOG" >&2; }

NEW_MAIN="$(ls -1t "${ESP_DIR}"/vmlinuz-*.EFI 2>/dev/null | grep -v -- '-backup\.EFI$' | head -n1 || true)"
if [[ -z "$NEW_MAIN" ]]; then
  log "No vmlinuz-*.EFI found in ${ESP_DIR}; nothing to do."
  exit 0
fi

base="${NEW_MAIN%.EFI}"
BUILDER_BKP="${base}-backup.EFI"

if [[ -f "$BUILDER_BKP" ]]; then
  log "Using builder backup $(basename "$BUILDER_BKP") -> ZFSBootMenu-fallback.EFI"
  mv -f "$BUILDER_BKP" "${ESP_DIR}/ZFSBootMenu-fallback.EFI"
elif [[ -f "${ESP_DIR}/ZFSBootMenu.EFI" ]]; then
  log "No builder backup; preserving current ZFSBootMenu.EFI -> ZFSBootMenu-fallback.EFI"
  mv -f "${ESP_DIR}/ZFSBootMenu.EFI" "${ESP_DIR}/ZFSBootMenu-fallback.EFI"
fi

log "Setting new stable: $(basename "$NEW_MAIN") -> ZFSBootMenu.EFI"
mv -f "$NEW_MAIN" "${ESP_DIR}/ZFSBootMenu.EFI"
SH
  chmod +x /etc/zfsbootmenu/generate-zbm.post.d/10-rename-uki.sh
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

    if command -v lsblk >/dev/null && lsblk --help 2>&1 | grep -q PARTNUM; then
      disk="/dev/$(lsblk -no PKNAME "${ESP_DEV}")"
      partnum="$(lsblk -no PARTNUM "${ESP_DEV}")"
    else
      disk="${ESP_DEV%[0-9]*}"
      partnum="${ESP_DEV##*[!0-9]}"
    fi

    efibootmgr -c -d "${disk}" -p "${partnum}" \
      -L "ZFSBootMenu" -l '\EFI\ZBM\ZFSBootMenu.EFI'
    say "Created UEFI entry: ZFSBootMenu"
  fi
}

ensure_initial_kernels_everywhere() {
  say "Final kernel sync to ensure everything has kernels..."

  # Make absolutely sure /boot has kernels
  if [[ ! -f /boot/vmlinuz-${KERNEL_BASENAME} ]]; then
    if [[ -f ${EFI_DIR}/vmlinuz-${KERNEL_BASENAME} ]]; then
      cp ${EFI_DIR}/vmlinuz-${KERNEL_BASENAME} /boot/
      cp ${EFI_DIR}/initramfs-${KERNEL_BASENAME}*.img /boot/
    else
      pacman -S --noconfirm ${KERNEL_BASENAME}
    fi
  fi

  # And ESP has kernels
  if [[ ! -f ${EFI_DIR}/vmlinuz-${KERNEL_BASENAME} ]]; then
    cp /boot/vmlinuz-${KERNEL_BASENAME} ${EFI_DIR}/
    cp /boot/initramfs-${KERNEL_BASENAME}*.img ${EFI_DIR}/
  fi

  say "✓ Kernels present in both /boot and ESP"
}

final_checks() {
  say "Final configuration status:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  findmnt -no FSTYPE,SOURCE,TARGET /
  findmnt -no FSTYPE,SOURCE,TARGET /boot || true
  findmnt -no FSTYPE,SOURCE,TARGET "${EFI_DIR}" || true
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  zpool get bootfs "${POOL}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Kernel locations:"
  ls -la /boot/vmlinuz-* 2>/dev/null || echo "  None in /boot"
  ls -la ${EFI_DIR}/vmlinuz-* 2>/dev/null || echo "  None in ESP"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "ZBM will use: root=ZFS=${BE_DATASET}"
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
  set_zbm_dataset_properties
  ensure_kernel_files_in_boot
  ensure_mkinitcpio_has_zfs
  write_zbm_config
  write_dracut_conf
  install_pre_snapshot_hook
  write_post_hook_rename
  install_generate_zbm_hook
  install_copy_kernel_to_esp_hook
  ensure_initial_kernels_everywhere
  generate_zbm_images
  create_uefi_entry_if_missing
  final_checks

  if [[ "${PERSISTENT_ESP}" != "true" ]]; then
    say "Un-mounting ESP (ZBM will mount it on demand)…"
    umount "${EFI_DIR}" || true
  fi

  say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  say "✓ Setup complete!"
  say ""
  say "Key changes made:"
  say "• Kernels kept in /boot (on root dataset) for snapshots"
  say "• Kernels mirrored to ESP for ZBM to use"
  say "• Pre-snapshot hook ensures kernels before snapshot"
  say "• ZBM configured to use ESP kernels for all BEs"
  say ""
  say "This means:"
  say "• All snapshots will include kernel files"
  say "• Cloned BEs will be immediately bootable"
  say "• No need to manually sync kernels"
  say "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
