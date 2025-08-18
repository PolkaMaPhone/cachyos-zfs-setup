# CachyOS ZFS Setup

Opinionated ZFS setup for CachyOS providing ZFSBootMenu boot environments, automatic pacman snapshots and an optional systemd-boot fallback.

## Features
- ZFSBootMenu-managed boot environments
- Automatic pacman snapshots with pruning
- Monthly zpool scrub timer
- Fish shell helpers
- Optional systemd-boot fallback

## Assumptions
- CachyOS with systemd-boot
- Root filesystem on ZFS
- ESP mounted at `/efi`
- `/boot` is a directory inside each boot environment dataset

## Quick start
Run everything in one shot (replace `/dev/nvme0n1p1` with your ESP device):
```bash
curl -fsSL https://raw.githubusercontent.com/polkamaphone/cachyos-zfs-setup/main/all-in-one.sh | sudo bash -s -- /dev/nvme0n1p1
```
The script clones this repository, installs helpers, configures ZFSBootMenu and runs validation. If the ESP device looks suspicious, it will warn before proceeding.

### Manual steps
```bash
git clone https://github.com/polkamaphone/cachyos-zfs-setup.git
cd cachyos-zfs-setup

# install pacman hooks and helpers
sudo ./install.sh
# disable systemd-boot mirroring:
# USE_SYSTEMD_BOOT_FALLBACK=false sudo ./install.sh

# configure ZFSBootMenu (use ESP partition path)
sudo ./system-scripts/zbm-setup.sh /dev/nvme0n1p1
```
Reboot and select **ZFSBootMenu**.

### Find your ESP
```bash
findmnt -no SOURCE /efi
# or
lsblk -o NAME,PATH,SIZE,FSTYPE,PARTLABEL | grep -iE 'efi|vfat'
```

## Sanity checks
```bash
findmnt /boot    # ZFS path inside BE
findmnt /efi     # vfat ESP
zpool get bootfs <pool>
ls /boot         # kernel + initramfs or UKI present
```

## Fish shortcuts
Run `exec fish` once, then:
```bash
zsi             # list snapshots
zfs-mount-info  # show dataset for /
ztc             # create test clone from latest snapshot
```

## Uninstall
```bash
sudo rm /etc/pacman.d/hooks/{00-zfs-pre-snapshot.hook,99-zfs-prune-snapshots.hook,90-generate-zbm.hook,10-copy-kernel-to-esp.hook} 2>/dev/null
sudo rm /usr/local/sbin/{zfs-pre-pacman-snapshot.sh,zfs-prune-pacman-snapshots.sh,copy-kernel-to-esp.sh} 2>/dev/null
```
