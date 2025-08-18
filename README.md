# CachyOS ZFS Setup

Personal CachyOS configuration with ZFS boot environments and comprehensive automation.

## Features

- **ZFS Boot Environments** with ZFSBootMenu
- **Automated snapshots** before pacman operations  
- **Automated cleanup** of old snapshots
- **Monthly pool scrubbing** for data integrity
- **Fish shell** with comprehensive ZFS management functions
- **Dual bootloader** setup (ZBM + systemd-boot fallback)

## Quick Install (Existing System)

```bash
git clone git@github.com:polkamaphone/cachyos-zfs-setup.git
cd cachyos-zfs-setup
sudo ./install.sh
