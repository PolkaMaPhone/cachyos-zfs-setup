# CachyOS ZFS Setup

Personal CachyOS configuration with ZFS boot environments and comprehensive automation.

## Features

- **ZFS Boot Environments** with ZFSBootMenu
- **Automated snapshots** before pacman operations  
- **Automated cleanup** of old snapshots
- **Monthly pool scrubbing** for data integrity
- **Fish shell** with comprehensive ZFS management functions
- **Dual bootloader** setup (ZBM + systemd-boot fallback)

## Assumptions:

- ** CachyOS with systemd-boot on zfs filesystem


## Recommended Installation flow
 
```bash

git clone https://github.com/polkamaphone/cachyos-zfs-setup.git
cd cachyos-zfs-setup

# 1. Initial setup (no hooks activated)
sudo ./install.sh

# 2. Configure ZBM (ensures kernels in /boot)
sudo ./system-scripts/zbm-setup.sh /dev/nvme0n1p1

# 3. Complete setup (activates hooks)
sudo /usr/local/sbin/finish-zfs-setup.sh
