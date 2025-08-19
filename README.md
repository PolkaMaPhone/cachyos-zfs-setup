# CachyOS ZFS Setup

Opinionated ZFS setup for CachyOS providing ZFSBootMenu boot environments, automatic pacman snapshots and an optional systemd-boot fallback.

## Features
- ZFSBootMenu-managed boot environments
- Automatic pacman snapshots with pruning
- Monthly zpool scrub timer
- Fish shell helpers
- Optional systemd-boot fallback

## Fish Shell Integration

The installer provides per-user Fish shell integration through conf.d snippets and ZFS helper functions.

### What Gets Installed
- **Functions**: Only `zfs-*` functions are copied to `~/.config/fish/functions/`
- **Configuration**: Environment variables and abbreviations via `~/.config/fish/conf.d/` snippets
- **Version**: `CACHYOS_ZFS_HELPERS_VERSION` environment variable for version tracking

### Configuration Details
Three conf.d snippets provide the integration:
- `00-cachyos-zfs-version.fish` - Sets version info and handles disable flags
- `20-cachyos-zfs-env.fish` - ZFS environment variables (only if not already set)
- `30-cachyos-zfs-abbr.fish` - ZFS command abbreviations

### Environment Variables
Default values set only if not already defined:
```fish
ZFS_ROOT_POOL="zpcachyos"
ZFS_ROOT_DATASET="zpcachyos/ROOT/cos/root"  
ZFS_HOME_DATASET="zpcachyos/ROOT/cos/home"
ZFS_VARCACHE_DATASET="zpcachyos/ROOT/cos/varcache"
ZFS_VARLOG_DATASET="zpcachyos/ROOT/cos/varlog"
ZFS_BE_ROOT="zpcachyos/ROOT"
ZFS_SHOW_COMMANDS=true
```

### Available Abbreviations
```fish
zls    -> zfs-list-snapshots
zsi    -> zfs-list-snapshots  
zcs    -> zfs-config-show
ztc    -> zfs-be-test-clone
zbi    -> zfs-be-info --all
zspace -> zfs-space
zfs-mount-info -> findmnt -no SOURCE /
```

### Disabling Helpers
To disable all ZFS helpers:
```fish
set -gx CACHYOS_ZFS_DISABLE 1
```

To disable only abbreviations:
```fish
set -gx CACHYOS_ZFS_DISABLE_ABBR 1
```

### User's config.fish Untouched
The installer never modifies your `~/.config/fish/config.fish` file. All integration is done through functions and conf.d snippets that Fish loads automatically.

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

## Quick Fish Usage
After installation, start a new Fish session and use the abbreviations:
```fish
zsi             # list snapshots (zfs-list-snapshots)
zfs-mount-info  # show dataset for / (findmnt -no SOURCE /)
ztc             # create test clone from latest snapshot (zfs-be-test-clone)
zcs             # show ZFS configuration (zfs-config-show)
zspace          # ZFS space analysis (zfs-space)
```

Check integration status:
```fish
echo $CACHYOS_ZFS_HELPERS_VERSION  # Should show "1.0.0"
```

## Uninstall
```bash
sudo rm /etc/pacman.d/hooks/{00-zfs-pre-snapshot.hook,99-zfs-prune-snapshots.hook,90-generate-zbm.hook,10-copy-kernel-to-esp.hook} 2>/dev/null
sudo rm /usr/local/sbin/{zfs-pre-pacman-snapshot.sh,zfs-prune-pacman-snapshots.sh,copy-kernel-to-esp.sh} 2>/dev/null
```
