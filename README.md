# CachyOS ZFS Setup

Opinionated CachyOS setup with **ZFS Boot Environments** (via **ZFSBootMenu**), **automatic snapshots**, and an optional **systemd-boot fallback**. Designed to be reproducible and idempotent.

## Features

- **ZFS Boot Environments** managed by ZFSBootMenu (ZBM)
- **Automated pacman snapshots** (PreTransaction) with **auto-prune**
- **Monthly ZFS pool scrub** timer
- **Fish shell** with handy ZFS functions/abbreviations
- **Dual bootloader**: ZBM primary, **systemd-boot fallback** (optional)

## Assumptions

- You’re on **CachyOS** using **systemd-boot**.
- Your root filesystem is **ZFS** and you want ZBM to manage boot environments.
- The **EFI System Partition (ESP)** is (or will be) mounted at **`/efi`**.
- **`/boot` is a directory inside each boot environment dataset** (not a vfat mount).  
  > ZBM only lists a BE if that dataset’s **`/boot` contains a kernel + initramfs (or a UKI)**.
- Recommended pool layout:
  ```text
  <pool>/ROOT            (mountpoint=none)
  <pool>/ROOT/cos/root   (canmount=noauto, mountpoint=/)
  ```

---

## Installation (2 steps)

```bash
git clone https://github.com/polkamaphone/cachyos-zfs-setup.git
cd cachyos-zfs-setup

# 1) Base install (installs pacman hooks & helpers)
#    Optional: disable systemd-boot fallback mirroring with:
#    USE_SYSTEMD_BOOT_FALLBACK=false sudo ./install.sh
sudo ./install.sh

# 2) Configure ZFSBootMenu and seed kernel/initramfs into each BE’s /boot
#    ⚠️ This takes a block device **partition** path for your ESP (e.g. /dev/nvme0n1p1)
sudo ./system-scripts/zbm-setup.sh /dev/your_esp_partition
```

Then reboot and confirm ZFSBootMenu appears.

---

## ⚠️ Safely choosing the ESP for `zbm-setup.sh`

Passing the wrong device here can brick your boot. Choose carefully:

1. **If `/efi` is already mounted**, prefer using that exact device:
   ```bash
   findmnt -no SOURCE /efi
   # Example output: /dev/nvme0n1p1  ← pass this to zbm-setup.sh
   ```

2. **If `/efi` is not mounted**, identify the ESP by type/flags:
   ```bash
   lsblk -o NAME,PATH,SIZE,FSTYPE,PARTLABEL,PARTUUID,MOUNTPOINTS | grep -iE 'efi|vfat'
   # Look for a small FAT32 partition labeled "EFI System" (vfat, ~100–500MB)
   ```

3. **Double-check with efibootmgr** (optional sanity):
   ```bash
   sudo efibootmgr -v | sed -n 's/.*File(\\EFI\\.*)/&/p'
   ```

👉 **Pass the *partition* device**, e.g. `/dev/nvme0n1p1`, **not the whole disk** (`/dev/nvme0n1`).

---

## Post-install sanity checklist (quick)

- `findmnt /boot` → should show a **ZFS** mount inside your BE (not vfat).  
- `findmnt /efi` → should show your **ESP** (vfat).  
- `zpool get bootfs <pool>` → should be your active BE dataset (e.g. `zpcachyos/ROOT/cos/root`).  
- `ls /boot` → must contain **kernel + initramfs** or a **UKI**.

---

## Built-in fish shortcuts

After install, run `exec fish` once to load functions/abbrs. Notables:

- `zsi` → `zfs list -t snapshot -o name,used,refer,creation -s creation`
- `zfs-mount-info` → `findmnt -no SOURCE /` (which dataset you’re booted into)
- `ztc` → creates a **test clone** boot environment from the most recent pacman snapshot

---

## Validation flow (suggested)

1. `exec fish`  
2. `zsi` → **Expect no pacman snapshots yet** (fresh install).  
3. `zfs-mount-info` → **Expect** something like `zpcachyos/ROOT/cos/root`.  
4. **Create a snapshot safely**:
   - EITHER force a small, safe pacman action:
     ```bash
     sudo pacman -S --reinstall --noconfirm zlib  # or another tiny core pkg
     ```
     (Triggers the PreTransaction snapshot hook.)
   - OR directly call the pre-snapshot helper (no package change):
     ```bash
     sudo /usr/local/sbin/zfs-pre-pacman-snapshot.sh
     ```
5. `zsi` again → **Expect** a new `@pacman-YYYYMMDD-HHMMSS` snapshot.  
6. `ztc` → creates a `test-YYYYMMDD-HHMMSS` BE from that pacman snapshot.  
7. Reboot → ZFSBootMenu → press **Esc** for the menu → choose the **new test BE**.  
8. After boot, `zfs-mount-info` → **Expect** `zpcachyos/ROOT/test-.../root`.

---

## How it works (short version)

- **Hooks** (installed by `install.sh`):
  - `00-zfs-pre-snapshot.hook` → before pacman transactions, snapshot the **active BE** (skips automatically if a BE isn’t bootable yet).
  - `99-zfs-prune-snapshots.hook` → keep the last 20 pacman snapshots.
  - `90-generate-zbm.hook` → regenerate ZBM EFI images after kernel/initramfs changes.
  - `10-copy-kernel-to-esp.hook` *(optional)* → mirror `/boot` kernel/initramfs (or UKIs) to `/efi/EFI/Linux/` as a **systemd-boot fallback**.
- **ZBM expectations**:
  - Each BE’s dataset (mounting at `/`) must include **`/boot`** with **kernel + initramfs** or a **UKI**.
  - Do **not** include `root=` in `org.zfsbootmenu:commandline`; ZBM injects it automatically.

---

---

## Reference pool layouts (CachyOS GUI defaults)

If you chose **ZFS** in the CachyOS GUI installer and let it partition the whole disk with defaults, you'll typically see a layout like the following.

### Example: Production workstation
```text
zpcachyos                    80.4G  1.68T    96K  none
zpcachyos/ROOT               80.3G  1.68T    96K  none
zpcachyos/ROOT/cos           80.3G  1.68T   257M  none
zpcachyos/ROOT/cos/home      50.8G  1.68T  50.8G  /home
zpcachyos/ROOT/cos/root      19.3G  1.68T  14.0G  /
zpcachyos/ROOT/cos/varcache  9.89G  1.68T  9.89G  /var/cache
zpcachyos/ROOT/cos/varlog     268K  1.68T   268K  /var/log
```

### Example: Test system after creating a test BE
```text
zpcachyos                                 4.18G  24.4G    96K  none
zpcachyos/ROOT                            4.18G  24.4G    96K  none
zpcachyos/ROOT/cos                        4.18G  24.4G    96K  none
zpcachyos/ROOT/cos/home                   9.71M  24.4G  9.71M  /home
zpcachyos/ROOT/cos/root                   3.16G  24.4G  3.13G  /
zpcachyos/ROOT/cos/varcache               1.00G  24.4G  1.00G  /var/cache
zpcachyos/ROOT/cos/varlog                  160K  24.4G   160K  /var/log
zpcachyos/ROOT/test-20250818-114452       1.06M  24.4G    96K  none
zpcachyos/ROOT/test-20250818-114452/root   992K  24.4G  3.13G  /
```

### What this means

- `zpcachyos/ROOT` is a **container** (mountpoint=none).  
- CachyOS places the active boot environment in a **`/root` child** under a container dataset (here: `zpcachyos/ROOT/cos/root`).  
- Other paths like `/home`, `/var/cache`, `/var/log` are their own datasets under the same container (`.../cos/*`).  
- When you create a new boot environment, you’ll see another container (e.g. `zpcachyos/ROOT/test-<timestamp>`) with its own `root` child.

### ZBM requirements with this layout

- ZBM discovers bootable entries by scanning datasets that **mount at `/`** (e.g. `.../cos/root`, `.../test-.../root`).  
- Each such dataset must have a **`/boot` directory containing kernel + initramfs (or a UKI)**.  
- **Do not** mount the ESP at `/boot`; the ESP should be at `/efi`. `/boot` lives **inside the BE**.

### Snapshot/clone targets (important)

- **Snapshot the dataset that mounts at `/`**:  
  ```bash
  # Good:
  zfs snapshot zpcachyos/ROOT/cos/root@pacman-YYYYMMDD-HHMMSS
  # Not helpful for ZBM menus:
  zfs snapshot zpcachyos/ROOT/cos@...  # (parent container, ZBM won't show it)
  ```
- **Clone to create a BE** (container + /root child):
  ```bash
  ts=$(date +%Y%m%d-%H%M%S)
  zfs clone zpcachyos/ROOT/cos/root@pacman-<when> zpcachyos/ROOT/test-$ts/root
  zfs set canmount=noauto zpcachyos/ROOT/test-$ts/root
  ```

### Sanity checks

```bash
# Which dataset will boot by default?
zpool get bootfs zpcachyos

# All root-like datasets (mount at '/' or canmount=noauto)
zfs list -H -o name,mountpoint,canmount -r zpcachyos/ROOT   | awk '$2=="/" || $3=="noauto"{print $1}'

# Does the active BE have kernels in /boot?
ls -l /boot
```

> This repo and its scripts support both the **container+`/root` child** layout (CachyOS default) and the **single-filesystem-per-BE** layout. You don’t need to change your layout—just ensure `/boot` lives **inside** the BE dataset.

## Troubleshooting

**ZBM says**: “failed to find kernels on <dataset>”  
→ That dataset’s `/boot` is missing kernel/initramfs (or UKI). From ZBM recovery shell:
```bash
zfs-chroot <pool>/ROOT/<be>/root
mkinitcpio -P   # or dracut if you’re using dracut
exit
```
Also ensure `/boot` is **not** your ESP; `/boot` must live **inside the BE dataset**.

**Snapshots don’t show in ZBM**  
→ Snapshots are **per-dataset**. Make sure you’re snapshotting the dataset that mounts at `/` (e.g. `.../root@...`), not a parent like `.../cos@...`).

**ESP confusion**  
→ Use `findmnt -no SOURCE /efi`. If empty, find the vfat partition via `lsblk`, then:
```bash
sudo mount /dev/nvme0n1p1 /efi   # adjust your device
```

**Roll back a bad update**  
→ At the ZBM menu, choose a previous BE (or a BE created from an earlier pacman snapshot). That’s why we snapshot before every transaction.

---

## Optional toggles

- Disable fallback mirroring during install:
  ```bash
  USE_SYSTEMD_BOOT_FALLBACK=false sudo ./install.sh
  ```

---

## Uninstall (hooks & helpers)

```bash
sudo rm /etc/pacman.d/hooks/{00-zfs-pre-snapshot.hook,99-zfs-prune-snapshots.hook,90-generate-zbm.hook,10-copy-kernel-to-esp.hook} 2>/dev/null
sudo rm /usr/local/sbin/{zfs-pre-pacman-snapshot.sh,zfs-prune-pacman-snapshots.sh,copy-kernel-to-esp.sh} 2>/dev/null
```
