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

## Fish Integration
The installer sets up minimal, per-user Fish shell integration focused solely on ZFS functionality.

### Installed Files
After running `sudo ./install.sh`, the following files are installed to the user's home directory:
- `~/.config/fish/functions/zfs-*.fish` - ZFS helper functions (16 functions)
- `~/.config/fish/conf.d/00-cachyos-zfs-version.fish` - Version information
- `~/.config/fish/conf.d/20-cachyos-zfs-env.fish` - Environment variable defaults
- `~/.config/fish/conf.d/30-cachyos-zfs-abbr.fish` - Convenient abbreviations

### Disable Options
Disable all ZFS helpers:
```bash
set -Ux CACHYOS_ZFS_DISABLE 1
```

Disable only abbreviations (keep functions and environment):
```bash
set -Ux CACHYOS_ZFS_DISABLE_ABBR 1
```

### Available Abbreviations  
Run `exec fish` once, then use these shortcuts:
```bash
zls             # zfs-list-snapshots
zsi             # zfs-list-snapshots (alias)
zcs             # zfs-config-show
ztc             # zfs-be-test-clone
zbi             # zfs-be-info --all
zspace          # zfs-space
zfs-mount-info  # findmnt -no SOURCE /
```

### Environment Variables
The following ZFS environment variables are set automatically (only if not already defined):
- `ZFS_ROOT_POOL` (default: "zpcachyos")
- `ZFS_ROOT_DATASET` (default: "zpcachyos/ROOT/cos/root")
- `ZFS_HOME_DATASET` (default: "zpcachyos/ROOT/cos/home")
- `ZFS_VARCACHE_DATASET` (default: "zpcachyos/ROOT/cos/varcache")
- `ZFS_VARLOG_DATASET` (default: "zpcachyos/ROOT/cos/varlog")
- `ZFS_BE_ROOT` (default: "zpcachyos/ROOT")
- `ZFS_SHOW_COMMANDS` (default: true)

### Version Information
Check the installed version:
```bash
echo $CACHYOS_ZFS_HELPERS_VERSION  # Shows: 1.0.0
```

## Uninstall
```bash
sudo rm /etc/pacman.d/hooks/{00-zfs-pre-snapshot.hook,99-zfs-prune-snapshots.hook,90-generate-zbm.hook,10-copy-kernel-to-esp.hook} 2>/dev/null
sudo rm /usr/local/sbin/{zfs-pre-pacman-snapshot.sh,zfs-prune-pacman-snapshots.sh,copy-kernel-to-esp.sh} 2>/dev/null
```
