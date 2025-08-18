#!/usr/bin/env bash
set -euo pipefail

POOL="zpcachyos"
BE_DATASET="$(zpool get -H -o value bootfs "$POOL")"
ESP_DIR="/efi"  # ESP now mounted here
KERNEL="${ESP_DIR}/vmlinuz-linux-cachyos"
INITRD="${ESP_DIR}/initramfs-linux-cachyos.img"
AMD_UCODE="${ESP_DIR}/amd-ucode.img"
INTEL_UCODE="${ESP_DIR}/intel-ucode.img"

# If root is the BE, copy directly into /boot; otherwise do a temp mount
ROOT_SRC="$(findmnt -no SOURCE / || true)"
if [[ "$ROOT_SRC" == "$BE_DATASET" ]]; then
  sudo mkdir -p /boot
  sudo install -m0644 "$KERNEL" "$INITRD" /boot/
  [[ -f "$AMD_UCODE"   ]] && sudo install -m0644 "$AMD_UCODE"   /boot/
  [[ -f "$INTEL_UCODE" ]] && sudo install -m0644 "$INTEL_UCODE" /boot/
else
  TMP_MNT="/run/zbm-be-$$"
  sudo zfs set canmount=noauto "$BE_DATASET"
  sudo zfs set mountpoint="$TMP_MNT" "$BE_DATASET"
  sudo mkdir -p "$TMP_MNT"
  sudo zfs mount "$BE_DATASET"
  sudo mkdir -p "$TMP_MNT/boot"
  sudo install -m0644 "$KERNEL" "$INITRD" "$TMP_MNT/boot/"
  [[ -f "$AMD_UCODE"   ]] && sudo install -m0644 "$AMD_UCODE"   "$TMP_MNT/boot/"
  [[ -f "$INTEL_UCODE" ]] && sudo install -m0644 "$INTEL_UCODE" "$TMP_MNT/boot/"
  sudo zfs umount "$BE_DATASET"
  sudo zfs set mountpoint=none "$BE_DATASET"
  sudo zfs set canmount=off "$BE_DATASET"
fi
echo "[zbm-sync] done"
