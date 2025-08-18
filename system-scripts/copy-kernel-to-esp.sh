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
