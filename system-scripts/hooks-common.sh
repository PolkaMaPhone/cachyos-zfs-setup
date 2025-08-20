#!/usr/bin/env bash
# Common pacman hook installers for CachyOS ZFS setup

set -euo pipefail

: "${KERNEL_BASENAME:=linux-cachyos}"
: "${SNAPSHOT_KEEP:=20}"
: "${BATCH_WINDOW:=3}"
: "${ESP_DEV:=}"

install_pre_snapshot_hook() {
    install -d /usr/local/sbin /etc/pacman.d/hooks
    cat >/usr/local/sbin/zfs-pre-pacman-snapshot.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

BATCH_WINDOW="\${BATCH_WINDOW:-${BATCH_WINDOW}}"
BE="\$(findmnt -no SOURCE /)"

if [[ -z "\$BE" ]]; then
  echo "[zfs-pre-snap] Could not detect root dataset" >&2
  exit 1
fi

if [[ ! -f /boot/vmlinuz-${KERNEL_BASENAME} ]]; then
  echo "[zfs-pre-snap] Ensuring kernel files in /boot before snapshot..."
  if [[ -f /efi/vmlinuz-${KERNEL_BASENAME} ]]; then
    cp /efi/vmlinuz-${KERNEL_BASENAME} /boot/
    cp /efi/initramfs-${KERNEL_BASENAME}*.img /boot/ 2>/dev/null || true
    [[ -f /efi/amd-ucode.img ]] && cp /efi/amd-ucode.img /boot/
    [[ -f /efi/intel-ucode.img ]] && cp /efi/intel-ucode.img /boot/
  else
    echo "[zfs-pre-snap] Reinstalling kernel package to populate /boot..."
    pacman -S --noconfirm ${KERNEL_BASENAME}
  fi
fi

RECENT_SNAP=\$(zfs list -H -t snapshot -o name,creation -s creation -r "\$BE" 2>/dev/null | \\
  grep "@pacman-" | tail -1 || true)

if [[ -n "\$RECENT_SNAP" ]]; then
  SNAP_NAME=\$(echo "\$RECENT_SNAP" | awk '{print \$1}')
  SNAP_TIME=\$(echo "\$RECENT_SNAP" | awk '{\$1=""; print \$0}' | sed 's/^ *//')
  SNAP_EPOCH=\$(date -d "\$SNAP_TIME" +%s 2>/dev/null || echo "0")
  CURRENT_EPOCH=\$(date +%s)
  WINDOW_SECONDS=\$((BATCH_WINDOW * 60))
  if [[ \$SNAP_EPOCH -gt 0 ]] && [[ \$((CURRENT_EPOCH - SNAP_EPOCH)) -lt \$WINDOW_SECONDS ]]; then
    AGE_SEC=\$(( CURRENT_EPOCH - SNAP_EPOCH ))
    echo "[zfs-pre-snap] Recent snapshot exists (\${AGE_SEC}s ago), skipping"
    exit 0
  fi
fi

STAMP="\$(date +%Y%m%d-%H%M%S)"
TAG="pacman-\${STAMP}"
echo "[zfs-pre-snap] Creating snapshot \${BE}@\${TAG}"
zfs snapshot "\${BE}@\${TAG}"
zfs set custom:pacman_version="\$(pacman -Q pacman | cut -d' ' -f2)" "\${BE}@\${TAG}"
zfs set custom:kernel_version="\$(uname -r)" "\${BE}@\${TAG}"
zfs set custom:package_count="\$(pacman -Q | wc -l)" "\${BE}@\${TAG}"
echo "[zfs-pre-snap] Snapshot created with kernel files included"
exit 0
EOF
    chmod 0755 /usr/local/sbin/zfs-pre-pacman-snapshot.sh

    cat >/etc/pacman.d/hooks/00-zfs-pre-snapshot.hook <<'EOF'
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
EOF
}

install_prune_snapshots_hook() {
    install -d /usr/local/sbin /etc/pacman.d/hooks
    local BE_EXPR='${BE}'
    cat >/usr/local/sbin/zfs-prune-pacman-snapshots.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
KEEP=\${KEEP:-${SNAPSHOT_KEEP}}
BE="\$(findmnt -no SOURCE /)"
[[ -z "\$BE" ]] && exit 1
mapfile -t snaps < <(zfs list -H -t snapshot -o name -s creation | grep "^${BE_EXPR}@pacman-")
if (( \${#snaps[@]} > KEEP )); then
    del_count=\$(( \${#snaps[@]} - KEEP ))
    printf "%s\n" "\${snaps[@]:0:del_count}" | xargs -r -n1 zfs destroy
    echo "[zfs-prune] Removed \$del_count old snapshot(s)"
fi
EOF
    chmod 0755 /usr/local/sbin/zfs-prune-pacman-snapshots.sh

    cat >/etc/pacman.d/hooks/99-zfs-prune-snapshots.hook <<'EOF'
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
EOF
}

install_generate_zbm_hook() {
    install -d /etc/pacman.d/hooks
    cat >/etc/pacman.d/hooks/90-generate-zbm.hook <<'EOF'
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
EOF
}

install_copy_kernel_to_esp_hook() {
    install -d /usr/local/sbin /etc/pacman.d/hooks
    cat >/usr/local/sbin/copy-kernel-to-esp.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
ESP=\${ESP:-/efi}
ESP_DEV=\${ESP_DEV:-}
K=/boot/vmlinuz-${KERNEL_BASENAME}
I=/boot/initramfs-${KERNEL_BASENAME}.img

if [[ -f "\$K" ]]; then
  echo "[copy-kernel] Ensuring kernels in /boot for future snapshots"
else
  echo "[copy-kernel] WARNING: No kernel in /boot - future snapshots won't be bootable!"
fi

mkdir -p "\$ESP"
mounted_before=false

if ! findmnt -no FSTYPE "\$ESP" 2>/dev/null | grep -qx 'vfat'; then
  if [[ -n "\$ESP_DEV" ]]; then
    echo "[copy-kernel] Mounting \$ESP_DEV at \$ESP"
    mount -t vfat "\$ESP_DEV" "\$ESP" || { echo "[copy-kernel] mount failed"; exit 0; }
    mounted_before=true
  else
    echo "[copy-kernel] \$ESP not mounted and ESP_DEV not set; skipping."
    exit 0
  fi
fi

[[ -f "\$K" ]] && install -m0644 "\$K" "\$ESP/"
[[ -f "\$I" ]] && install -m0644 "\$I" "\$ESP/"
[[ -f /boot/amd-ucode.img   ]] && install -m0644 /boot/amd-ucode.img   "\$ESP/"
[[ -f /boot/intel-ucode.img ]] && install -m0644 /boot/intel-ucode.img "\$ESP/"

\$mounted_before && umount "\$ESP" || true
exit 0
EOF
    chmod +x /usr/local/sbin/copy-kernel-to-esp.sh

    cat >/etc/pacman.d/hooks/10-copy-kernel-to-esp.hook <<EOF
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = ${KERNEL_BASENAME}
Target = amd-ucode
Target = intel-ucode
Target = linux-firmware-intel

[Action]
When = PostTransaction
Exec = /usr/bin/env ESP_DEV=${ESP_DEV:-} /usr/local/sbin/copy-kernel-to-esp.sh
Description = Mirror kernel/initramfs/microcode to ESP and ensure in /boot
EOF
}

