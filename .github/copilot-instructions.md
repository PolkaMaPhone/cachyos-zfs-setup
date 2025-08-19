# CachyOS ZFS Setup

CachyOS ZFS Setup is a collection of Bash shell scripts for configuring ZFS boot environments on CachyOS Linux. It provides ZFSBootMenu-managed boot environments, automatic pacman snapshots with pruning, monthly zpool scrub automation, Fish shell helpers, and optional systemd-boot fallback.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Working Effectively

### Prerequisites
- **CRITICAL**: This tool only works on CachyOS Linux with ZFS already installed and root filesystem on ZFS
- Requires ESP mounted at `/efi` and systemd-boot installed
- Must run as root with `sudo` (not direct root login)
- Network access for package installation

### Core Installation Workflow
Execute these commands in exact order:

```bash
# Clone repository
git clone https://github.com/polkamaphone/cachyos-zfs-setup.git
cd cachyos-zfs-setup

# Install pacman hooks and Fish shell helpers (takes ~30 seconds)
sudo ./install.sh

# Configure ZFSBootMenu with your ESP device - NEVER CANCEL, takes 3-5 minutes
# Replace /dev/nvme0n1p1 with your actual ESP partition
sudo ./system-scripts/zbm-setup.sh /dev/nvme0n1p1

# Validate setup (takes ~10 seconds)  
sudo ./validate-setup.sh
```

### One-Shot Installation Alternative
```bash
# WARNING: NEVER CANCEL - full process takes 5-8 minutes
curl -fsSL https://raw.githubusercontent.com/polkamaphone/cachyos-zfs-setup/main/all-in-one.sh | sudo bash -s -- /dev/nvme0n1p1
```

### Time Expectations and NEVER CANCEL Warnings
- **CRITICAL**: `sudo ./system-scripts/zbm-setup.sh` takes 3-5 minutes. NEVER CANCEL. Set timeout to 10+ minutes.
  - Package installation: 30-60 seconds
  - `mkinitcpio -P` (rebuild initramfs): 1-2 minutes  
  - `generate-zbm -d` (generate boot images): 1-2 minutes
- **CRITICAL**: `pacman -S` operations may take 30-60 seconds each. NEVER CANCEL. Set timeout to 5+ minutes.
- `./install.sh`: 10-30 seconds (file operations only)
- `./validate-setup.sh`: 5-10 seconds (check operations only)
- `./all-in-one.sh`: 5-8 minutes total. NEVER CANCEL. Set timeout to 15+ minutes.

### Key Package Dependencies
The system installs these packages automatically:
- **Core ZFS**: `zfsbootmenu`, `zfs-utils`, `efibootmgr`, `dosfstools`
- **Build tools**: `dracut`, `mkinitcpio`
- **System**: Installed via pacman from CachyOS repos

### Finding Your ESP Device
```bash
# Method 1: Check current mount
findmnt -no SOURCE /efi

# Method 2: List all EFI partitions
lsblk -o NAME,PATH,SIZE,FSTYPE,PARTLABEL | grep -iE 'efi|vfat'
```

## Validation

### Manual Validation Requirements
**ALWAYS** run these validation steps after making any changes:

```bash
# 1. Verify root filesystem is ZFS
findmnt -no SOURCE /  # Should show ZFS dataset path

# 2. Check ESP mount
findmnt -no FSTYPE /efi  # Should show 'vfat'

# 3. Verify ZFS pool bootfs property
zpool get bootfs $(zpool list -H -o name | head -1)

# 4. Check kernel files are present
ls -la /boot/vmlinuz* /boot/initramfs*

# 5. Run comprehensive validation - NEVER CANCEL, takes ~10 seconds
sudo ./validate-setup.sh
```

### Expected Validation Results
- All ZFS datasets properly configured with org.zfsbootmenu properties
- Pacman hooks installed: `/etc/pacman.d/hooks/{00-zfs-pre-snapshot.hook,99-zfs-prune-snapshots.hook,90-generate-zbm.hook}`
- Helper scripts: `/usr/local/sbin/{zfs-pre-pacman-snapshot.sh,zfs-prune-pacman-snapshots.sh}`
- ZFSBootMenu configuration: `/etc/zfsbootmenu/config.yaml`
- UEFI boot entry created for ZFSBootMenu
- Fish shell functions: 25 ZFS helper functions in `~/.config/fish/functions/`

### Validation Scenarios
After installation, test these specific scenarios:

1. **Snapshot Creation Test**:
   ```bash
   # Install a package to trigger pre-snapshot hook
   sudo pacman -S --noconfirm tree
   # Verify snapshot created
   zfs list -t snapshot | grep pacman-
   ```

2. **Fish Shell Helpers** (if Fish is installed):
   ```bash
   exec fish
   zsi  # List snapshots
   zfs-mount-info  # Show dataset for /
   ```

3. **Boot Environment Test**:
   ```bash
   # Check ZFSBootMenu images exist
   ls -la /efi/EFI/ZBM/
   # Should show ZFSBootMenu.EFI and related files
   ```

## Common Tasks

### Environment Variables
Set these to customize behavior:
```bash
USE_SYSTEMD_BOOT_FALLBACK=false  # Disable systemd-boot mirroring
SNAPSHOT_KEEP=30  # Keep more snapshots
KERNEL_BASENAME=linux-cachyos  # Different kernel
```

### Troubleshooting Commands
```bash
# Check ZFS health
zpool status
zfs list -o name,used,avail,refer,mountpoint

# Check boot environment
findmnt /boot  # Should be ZFS dataset
findmnt /efi   # Should be vfat ESP

# Check systemd services
systemctl status zpool-scrub@zpcachyos.timer
systemctl list-timers | grep scrub

# Check recent snapshots
zfs list -t snapshot -s creation | tail -5
```

### Common File Locations
- **Main scripts**: `./install.sh`, `./system-scripts/zbm-setup.sh`, `./validate-setup.sh`
- **Fish config**: `fish-shell/config.fish`, `fish-shell/functions/*.fish`
- **Package lists**: `packages/{native.txt,aur.txt,explicit.txt}`
- **System hooks**: `system-scripts/hooks-common.sh`
- **SystemD units**: `system-scripts/systemd-units/zpool-scrub@.{service,timer}`

## What CANNOT Be Done

### Limitations in Non-CachyOS Environments
- **Do NOT run these scripts on non-CachyOS systems** - they modify boot configuration and could render system unbootable
- ZFS commands will fail if ZFS is not installed
- Package installation via `pacman` only works on Arch-based systems
- ESP device validation requires actual ESP partitions

### Testing Alternatives
In development environments without ZFS:
- Use `bash -n script.sh` to validate shell script syntax
- Review but do not execute commands that modify system configuration  
- Test Fish shell functions only if Fish shell is installed
- Use `./esp-validate` to test ESP device validation logic

## Uninstallation
```bash
# Remove hooks and scripts
sudo rm -f /etc/pacman.d/hooks/{00-zfs-pre-snapshot.hook,99-zfs-prune-snapshots.hook,90-generate-zbm.hook,10-copy-kernel-to-esp.hook}
sudo rm -f /usr/local/sbin/{zfs-pre-pacman-snapshot.sh,zfs-prune-pacman-snapshots.sh,copy-kernel-to-esp.sh}

# Remove ZFSBootMenu configuration
sudo rm -rf /etc/zfsbootmenu

# Remove systemd units
sudo rm -f /etc/systemd/system/zpool-scrub@*
sudo systemctl daemon-reload
```

## Repository Structure Summary
```
├── README.md              # User documentation
├── all-in-one.sh         # Single-command bootstrap
├── install.sh            # Main installer (hooks, fish config)
├── validate-setup.sh     # Comprehensive validation
├── esp-validate          # ESP device validation
├── fish-shell/           # Fish shell configuration
│   ├── config.fish       # Main Fish config
│   └── functions/        # 25 ZFS helper functions
├── system-scripts/       # System integration
│   ├── zbm-setup.sh      # ZFSBootMenu configuration  
│   ├── hooks-common.sh   # Pacman hook generators
│   └── systemd-units/    # Scrub timer service
└── packages/             # Package dependency lists
```

## Critical Reminders
- **ALWAYS use sudo**: All main scripts require root privileges
- **NEVER CANCEL long operations**: Package installs and initramfs rebuilds take time
- **ESP device is critical**: Wrong ESP device will break boot process
- **Backup before running**: These scripts modify boot configuration
- **CachyOS only**: Will not work on other Linux distributions
- **Validate everything**: Always run `./validate-setup.sh` after changes