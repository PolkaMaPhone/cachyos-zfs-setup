#!/bin/bash
# validate-setup.sh - Comprehensive validation of ZFS + ZBM setup
# Run after installation to verify everything is configured correctly

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Global variables to store discovered values
ROOT_DATASET=""
ESP_PATH=""
POOL=""

# Test result functions
pass() {
    printf "${GREEN}✓${NC} %s\n" "$1"
    let PASSED+=1
}

fail() {
    printf "${RED}✗${NC} %s\n" "$1"
    let FAILED+=1
}

warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
    let WARNINGS+=1
}

header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Core system checks
check_root_on_zfs() {
    local fs_type=$(findmnt -no FSTYPE / 2>/dev/null || echo "unknown")

    if [[ "$fs_type" == "zfs" ]]; then
        ROOT_DATASET=$(findmnt -no SOURCE /)
        pass "Root on ZFS: $ROOT_DATASET"
    else
        fail "Root is not on ZFS (filesystem: $fs_type)"
    fi

}

check_boot_directory() {
    local boot_fs=$(findmnt -no FSTYPE /boot 2>/dev/null || echo "none")

    if [[ "$boot_fs" == "zfs" ]] || [[ "$boot_fs" == "none" ]]; then
        if [[ -d /boot ]] && [[ -f /boot/vmlinuz-linux-cachyos ]]; then
            pass "/boot is a directory on ZFS with kernel files"
        elif [[ -d /boot ]]; then
            fail "/boot exists but missing kernel files"
        else
            fail "/boot directory not found"
        fi
    else
        fail "/boot is on $boot_fs (should be on ZFS root dataset)"
    fi
}

check_esp_mount() {
    local esp_mounted=false

    for path in /efi /boot/efi; do
        if findmnt -no FSTYPE "$path" 2>/dev/null | grep -qx 'vfat'; then
            esp_mounted=true
            ESP_PATH="$path"
            break
        fi
    done

    if [[ "$esp_mounted" == "true" ]]; then
        local esp_dev=$(findmnt -no SOURCE "$ESP_PATH")
        pass "ESP mounted at $ESP_PATH ($esp_dev)"
    else
        warn "ESP not mounted (ZBM can mount on demand)"
        ESP_PATH=""
    fi
}

# ZFS configuration checks
check_zfs_pool() {
    POOL=$(zpool list -H -o name 2>/dev/null | head -n1 || echo "")

    if [[ -n "$POOL" ]]; then
        local health=$(zpool get -H -o value health "$POOL" 2>/dev/null || echo "UNKNOWN")
        if [[ "$health" == "ONLINE" ]]; then
            pass "ZFS pool '$POOL' is ONLINE"
        else
            warn "ZFS pool '$POOL' health: $health"
        fi
    else
        fail "No ZFS pools found"
    fi
}

check_bootfs_property() {
    if [[ -z "$POOL" ]]; then
        warn "Cannot check bootfs - no pool found"
        return
    fi

    local bootfs=$(zpool get -H -o value bootfs "$POOL" 2>/dev/null || echo "-")
    if [[ "$bootfs" != "-" ]] && [[ "$bootfs" != "" ]]; then
        pass "Boot filesystem set: $bootfs"
    else
        fail "No boot filesystem set on pool $POOL"
    fi
}

check_zbm_properties() {
    if [[ -z "$ROOT_DATASET" ]]; then
        warn "Cannot check ZBM properties - root dataset not detected"
        return
    fi

    # Extract pool and BE root from dataset
    local pool="${ROOT_DATASET%%/*}"
    local be_root="${ROOT_DATASET%/root}"

    # Check rootprefix
    local rootprefix=$(zfs get -H -o value org.zfsbootmenu:rootprefix "${pool}/ROOT" 2>/dev/null || echo "-")
    if [[ "$rootprefix" == "root=ZFS=" ]]; then
        pass "ZBM rootprefix configured correctly"
    else
        warn "ZBM rootprefix not set on ${pool}/ROOT"
    fi

    # Check commandline
    local cmdline=$(zfs get -H -o value org.zfsbootmenu:commandline "$ROOT_DATASET" 2>/dev/null || echo "-")
    if [[ -n "$cmdline" ]] && [[ "$cmdline" != "-" ]]; then
        pass "ZBM commandline set: $cmdline"
    else
        warn "No ZBM commandline on $ROOT_DATASET"
    fi
}

# ZFSBootMenu checks
check_zbm_config() {
    if [[ -f /etc/zfsbootmenu/config.yaml ]]; then
        pass "ZBM config exists: /etc/zfsbootmenu/config.yaml"

        # Check key settings
        if grep -q "BootMountPoint:" /etc/zfsbootmenu/config.yaml 2>/dev/null; then
            local mount=$(grep "BootMountPoint:" /etc/zfsbootmenu/config.yaml | awk '{print $2}' | tr -d '"')
            if [[ -n "$mount" ]]; then
                pass "ZBM boot mount point configured: $mount"
            fi
        fi
    else
        fail "ZBM config not found at /etc/zfsbootmenu/config.yaml"
    fi
}

check_zbm_images() {
    local esp="${ESP_PATH:-/efi}"
    local zbm_path="${esp}/EFI/ZBM"

    if [[ -d "$zbm_path" ]]; then
        local image_count=$(ls "$zbm_path"/*.EFI 2>/dev/null | wc -l)
        if [[ $image_count -gt 0 ]]; then
            pass "ZBM images found: $image_count EFI file(s) in $zbm_path"

            # Show most recent images
            ls -lht "$zbm_path"/*.EFI 2>/dev/null | head -n2 | while IFS= read -r line; do
                echo "    $line"
            done
        else
            fail "No ZBM EFI images in $zbm_path"
        fi
    else
        fail "ZBM directory not found: $zbm_path"
    fi
}

check_uefi_entry() {
    if ! command -v efibootmgr >/dev/null 2>&1; then
        warn "efibootmgr not available - cannot check UEFI entries"
        return
    fi

    if efibootmgr 2>/dev/null | grep -q "ZFSBootMenu"; then
        local entry=$(efibootmgr 2>/dev/null | grep "ZFSBootMenu" | head -n1)
        pass "UEFI entry exists: $entry"
    else
        warn "No ZFSBootMenu UEFI entry (add manually with efibootmgr)"
    fi
}

# Snapshot and automation checks
check_snapshots() {
    if [[ -z "$ROOT_DATASET" ]]; then
        warn "Cannot check snapshots - root dataset not detected"
        return
    fi

    local snap_count=$(zfs list -t snapshot -H -o name 2>/dev/null | grep "${ROOT_DATASET}@pacman-" | wc -l)

    if [[ $snap_count -gt 0 ]]; then
        pass "Pacman snapshots found: $snap_count"

        # Show most recent
        local recent=$(zfs list -t snapshot -H -o name,creation 2>/dev/null | grep "${ROOT_DATASET}@pacman-" | tail -n1)
        if [[ -n "$recent" ]]; then
            echo "    Most recent: $recent"
        fi
    else
        warn "No pacman snapshots found yet (will be created on next package operation)"
    fi
}

check_pacman_hooks() {
    local hooks_dir="/etc/pacman.d/hooks"
    local expected_hooks=(
        "00-zfs-pre-snapshot.hook"
        "99-zfs-prune-snapshots.hook"
        "90-generate-zbm.hook"
    )

    local found=0
    local missing=()

    for hook in "${expected_hooks[@]}"; do
        if [[ -f "$hooks_dir/$hook" ]]; then
            ((found++))
        else
            missing+=("$hook")
        fi
    done

    if [[ $found -eq ${#expected_hooks[@]} ]]; then
        pass "All essential pacman hooks installed ($found/${#expected_hooks[@]})"
    else
        fail "Some pacman hooks missing: ${missing[*]}"
    fi

    # Check for optional hook
    if [[ -f "$hooks_dir/10-copy-kernel-to-esp.hook" ]]; then
        pass "Optional systemd-boot fallback hook installed"
    fi
}

check_helper_scripts() {
    local scripts=(
        "/usr/local/sbin/zfs-pre-pacman-snapshot.sh"
        "/usr/local/sbin/zfs-prune-pacman-snapshots.sh"
    )

    local found=0
    local missing=()

    for script in "${scripts[@]}"; do
        if [[ -x "$script" ]]; then
            ((found++))
        else
            missing+=("$(basename "$script")")
        fi
    done

    if [[ $found -eq ${#scripts[@]} ]]; then
        pass "Helper scripts installed and executable"
    else
        fail "Some helper scripts missing or not executable: ${missing[*]}"
    fi
}

check_scrub_timer() {
    local pool="${POOL:-zpcachyos}"

    if systemctl is-enabled "zpool-scrub@${pool}.timer" &>/dev/null; then
        pass "Monthly scrub timer enabled for pool '$pool'"

        # Show next run time
        local next=$(systemctl show "zpool-scrub@${pool}.timer" --property=NextElapseUSecRealtime --value 2>/dev/null)
        if [[ -n "$next" ]] && [[ "$next" != "0" ]] && [[ "$next" != "" ]]; then
            local next_date=$(date -d "@$((next/1000000))" 2>/dev/null || echo "unknown")
            if [[ "$next_date" != "unknown" ]]; then
                echo "    Next scrub: $next_date"
            fi
        fi
    else
        warn "Scrub timer not enabled (enable with: systemctl enable --now zpool-scrub@${pool}.timer)"
    fi
}

check_kernel_locations() {
    local boot_kernel="/boot/vmlinuz-linux-cachyos"
    local boot_initramfs="/boot/initramfs-linux-cachyos.img"
    local esp="${ESP_PATH:-/efi}"

    if [[ -f "$boot_kernel" ]] && [[ -f "$boot_initramfs" ]]; then
        pass "Kernel files in /boot (for snapshots)"
    else
        fail "Kernel files missing from /boot"
    fi

    if [[ -n "$esp" ]] && [[ -d "$esp" ]]; then
        if [[ -f "$esp/vmlinuz-linux-cachyos" ]]; then
            pass "Kernel files in ESP (for ZBM)"
        else
            warn "Kernel files not in ESP (may cause boot issues)"
        fi
    fi
}

# Fish shell checks
check_fish_shell() {
    if command -v fish >/dev/null 2>&1; then
        pass "Fish shell installed"

        # Check if it's default for current user (when not root)
        if [[ "$USER" != "root" ]]; then
            local user_shell=$(getent passwd "$USER" | cut -d: -f7)
            if [[ "$user_shell" == "/usr/bin/fish" ]]; then
                pass "Fish is default shell for $USER"
            else
                warn "Fish not set as default shell (run: chsh -s /usr/bin/fish)"
            fi
        fi
    else
        warn "Fish shell not installed"
    fi
}

check_fish_functions() {
    local fish_dir="${HOME}/.config/fish"

    if [[ -d "$fish_dir/functions" ]]; then
        local func_count=$(ls "$fish_dir/functions"/zfs-*.fish 2>/dev/null | wc -l)
        if [[ $func_count -gt 0 ]]; then
            pass "Fish ZFS functions installed: $func_count functions"
        else
            warn "No ZFS fish functions found in $fish_dir/functions"
        fi
    else
        warn "Fish config directory not found at $fish_dir"
    fi
}

# Main validation
main() {
    echo "═══════════════════════════════════════"
    echo "   ZFS + ZFSBootMenu Setup Validator"
    echo "═══════════════════════════════════════"

    header "Core System"
    check_root_on_zfs
    check_boot_directory
    check_esp_mount

    header "ZFS Configuration"
    check_zfs_pool
    check_bootfs_property
    check_zbm_properties

    header "ZFSBootMenu"
    check_zbm_config
    check_zbm_images
    check_uefi_entry

    header "Kernel Locations"
    check_kernel_locations

    header "Snapshots & Automation"
    check_snapshots
    check_pacman_hooks
    check_helper_scripts
    check_scrub_timer

    header "Fish Shell"
    check_fish_shell
    check_fish_functions

    # Summary
    header "Validation Summary"
    echo "Passed:   $PASSED"
    echo "Failed:   $FAILED"
    echo "Warnings: $WARNINGS"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        if [[ $WARNINGS -eq 0 ]]; then
            printf "${GREEN}✓ All checks passed! Your system is properly configured.${NC}\n"
            exit 0
        else
            printf "${YELLOW}⚠ Setup complete with warnings. Review above for optional improvements.${NC}\n"
            exit 0
        fi
    else
        printf "${RED}✗ Setup has issues that need attention. Review failures above.${NC}\n"
        exit 1
    fi
}

# Run if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
