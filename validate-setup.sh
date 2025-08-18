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

# Test result functions
pass() {
    # Send result output to stderr so command substitutions only capture
    # explicit echo values from functions. This prevents assignments like
    # ROOT_DATASET=$(check_root_on_zfs) from including the status line in
    # the variable, which previously caused downstream commands (such as
    # snapshot detection) to fail.
    printf "${GREEN}✓${NC} %s\n" "$1" >&2
    let PASSED+=1
}

fail() {
    printf "${RED}✗${NC} %s\n" "$1" >&2
    let FAILED+=1
}

warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1" >&2
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
    if findmnt -no FSTYPE / | grep -qx 'zfs'; then
        local dataset=$(findmnt -no SOURCE /)
        pass "Root on ZFS: $dataset"
        echo "$dataset"  # Return for use in other checks
    else
        fail "Root is not on ZFS"
        return 1
    fi
}

check_boot_directory() {
    # Check if /boot is a separate mount point
    if findmnt /boot >/dev/null 2>&1; then
        local boot_fs=$(findmnt -no FSTYPE /boot)
        if [[ "$boot_fs" == "zfs" ]]; then
            pass "/boot is a ZFS dataset"
        elif [[ "$boot_fs" == "vfat" ]]; then
            fail "/boot is on ESP (vfat) - should be on ZFS for snapshots"
            return 1
        else
            fail "/boot is on $boot_fs (should be on ZFS)"
            return 1
        fi
    else
        # /boot is not a mount point - it's a directory on root
        if [[ -d /boot ]]; then
            if [[ -f /boot/vmlinuz-linux-cachyos ]]; then
                pass "/boot is a directory on root filesystem with kernel files"
            else
                warn "/boot exists but missing kernel files"
            fi
        else
            fail "/boot directory does not exist"
        fi
    fi
}

check_esp_mount() {
    local esp_mounted=false
    local esp_path=""

    for path in /efi /boot/efi; do
        if findmnt -no FSTYPE "$path" 2>/dev/null | grep -qx 'vfat'; then
            esp_mounted=true
            esp_path="$path"
            break
        fi
    done

    if [[ "$esp_mounted" == "true" ]]; then
        local esp_dev=$(findmnt -no SOURCE "$esp_path")
        pass "ESP mounted at $esp_path ($esp_dev)"
        echo "$esp_path"  # Return for use in other checks
    else
        warn "ESP not mounted (ZBM can mount on demand)"
        echo ""
    fi
}

# ZFS configuration checks
check_zfs_pool() {
    local pool=$(zpool list -H -o name 2>/dev/null | head -n1)

    if [[ -n "$pool" ]]; then
        local health=$(zpool get -H -o value health "$pool")
        if [[ "$health" == "ONLINE" ]]; then
            pass "ZFS pool '$pool' is ONLINE"
        else
            warn "ZFS pool '$pool' health: $health"
        fi
        echo "$pool"  # Return pool name
    else
        fail "No ZFS pools found"
        return 1
    fi
}

check_bootfs_property() {
    local pool="${1:-}"
    [[ -z "$pool" ]] && return 1

    local bootfs=$(zpool get -H -o value bootfs "$pool")
    if [[ "$bootfs" != "-" ]]; then
        pass "Boot filesystem set: $bootfs"
    else
        fail "No boot filesystem set on pool $pool"
    fi
}

check_zbm_properties() {
    local root_dataset="${1:-}"
    [[ -z "$root_dataset" ]] && return 1

    # Extract pool and BE root from dataset
    local pool="${root_dataset%%/*}"
    local be_root="${root_dataset%/root}"

    # Check rootprefix
    local rootprefix=$(zfs get -H -o value org.zfsbootmenu:rootprefix "${pool}/ROOT" 2>/dev/null || echo "")
    if [[ "$rootprefix" == "root=ZFS=" ]]; then
        pass "ZBM rootprefix configured correctly"
    else
        warn "ZBM rootprefix not set on ${pool}/ROOT"
    fi

    # Check commandline
    local cmdline=$(zfs get -H -o value org.zfsbootmenu:commandline "$root_dataset" 2>/dev/null || echo "")
    if [[ -n "$cmdline" ]] && [[ "$cmdline" != "-" ]]; then
        pass "ZBM commandline set: $cmdline"
    else
        warn "No ZBM commandline on $root_dataset"
    fi
}

# ZFSBootMenu checks
check_zbm_config() {
    if [[ -f /etc/zfsbootmenu/config.yaml ]]; then
        pass "ZBM config exists: /etc/zfsbootmenu/config.yaml"

        # Check key settings
        if grep -q "BootMountPoint:" /etc/zfsbootmenu/config.yaml; then
            local mount=$(grep "BootMountPoint:" /etc/zfsbootmenu/config.yaml | awk '{print $2}' | tr -d '"')
            pass "ZBM boot mount point: $mount"
        fi
    else
        fail "ZBM config not found"
    fi
}

check_zbm_images() {
    local esp_path="${1:-/efi}"
    local zbm_path="${esp_path}/EFI/ZBM"

    if [[ -d "$zbm_path" ]]; then
        local images=$(ls "$zbm_path"/*.EFI 2>/dev/null | wc -l)
        if [[ $images -gt 0 ]]; then
            pass "ZBM images found: $images EFI file(s) in $zbm_path"
            ls -lh "$zbm_path"/*.EFI 2>/dev/null | tail -n2 | while read line; do
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
    if command -v efibootmgr >/dev/null 2>&1; then
        if efibootmgr 2>/dev/null | grep -q "ZFSBootMenu"; then
            local entry=$(efibootmgr | grep "ZFSBootMenu" | head -n1)
            pass "UEFI entry exists: $entry"
        else
            warn "No ZFSBootMenu UEFI entry (add manually with efibootmgr)"
        fi
    else
        warn "efibootmgr not available - cannot check UEFI entries"
    fi
}

# Snapshot and automation checks
check_snapshots() {
    local root_dataset="${1:-}"
    [[ -z "$root_dataset" ]] && return 1

    local snap_count=$(zfs list -t snapshot -H -o name -r "$root_dataset" 2>/dev/null | grep "@pacman-" | wc -l)

    if [[ $snap_count -gt 0 ]]; then
        pass "Pacman snapshots found: $snap_count"

        # Show most recent
        local recent=$(zfs list -t snapshot -H -o name,creation -r "$root_dataset" | grep "@pacman-" | tail -n1)
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
    for hook in "${expected_hooks[@]}"; do
        if [[ -f "$hooks_dir/$hook" ]]; then
            ((found++))
        fi
    done

    if [[ $found -eq ${#expected_hooks[@]} ]]; then
        pass "All pacman hooks installed ($found/${#expected_hooks[@]})"
    else
        warn "Some pacman hooks missing ($found/${#expected_hooks[@]} found)"
    fi
}

check_helper_scripts() {
    local scripts=(
        "/usr/local/sbin/zfs-pre-pacman-snapshot.sh"
        "/usr/local/sbin/zfs-prune-pacman-snapshots.sh"
    )

    local found=0
    for script in "${scripts[@]}"; do
        if [[ -x "$script" ]]; then
            ((found++))
        fi
    done

    if [[ $found -eq ${#scripts[@]} ]]; then
        pass "Helper scripts installed and executable"
    else
        fail "Some helper scripts missing or not executable"
    fi
}

check_scrub_timer() {
    local pool="${1:-zpcachyos}"

    if systemctl is-enabled "zpool-scrub@${pool}.timer" &>/dev/null; then
        pass "Monthly scrub timer enabled for pool '$pool'"

        # Show next run time
        local next=$(systemctl show "zpool-scrub@${pool}.timer" --property=NextElapseUSecRealtime --value 2>/dev/null)
        if [[ -n "$next" ]] && [[ "$next" != "0" ]]; then
            echo "    Next scrub: $(date -d "@$((next/1000000))" 2>/dev/null || echo "unknown")"
        fi
    else
        warn "Scrub timer not enabled (enable with: systemctl enable --now zpool-scrub@${pool}.timer)"
    fi
}

check_kernel_locations() {
    local boot_kernel="/boot/vmlinuz-linux-cachyos"
    local boot_initramfs="/boot/initramfs-linux-cachyos.img"
    local esp_path="${1:-/efi}"

    local status=0

    if [[ -f "$boot_kernel" ]] && [[ -f "$boot_initramfs" ]]; then
        pass "Kernel files in /boot (for snapshots)"
    else
        fail "Kernel files missing from /boot"
        status=1
    fi

    if [[ -n "$esp_path" ]]; then
        if [[ -f "$esp_path/vmlinuz-linux-cachyos" ]]; then
            pass "Kernel files in ESP (for ZBM)"
        else
            warn "Kernel files not in ESP (may cause boot issues)"
        fi
    fi

    return $status
}

# Fish shell checks
check_fish_shell() {
    if command -v fish >/dev/null 2>&1; then
        pass "Fish shell installed"

        # Check if it's default for current user
        local user_shell=$(getent passwd "$USER" | cut -d: -f7)
        if [[ "$user_shell" == "/usr/bin/fish" ]]; then
            pass "Fish is default shell for $USER"
        else
            warn "Fish not set as default shell (run: chsh -s /usr/bin/fish)"
        fi
    else
        warn "Fish shell not installed"
    fi
}

check_fish_functions() {
    local fish_dir="$HOME/.config/fish"

    if [[ -d "$fish_dir/functions" ]]; then
        local func_count=$(ls "$fish_dir/functions"/zfs-*.fish 2>/dev/null | wc -l)
        if [[ $func_count -gt 0 ]]; then
            pass "Fish ZFS functions installed: $func_count functions"
        else
            warn "No ZFS fish functions found"
        fi
    else
        warn "Fish config directory not found"
    fi
}

# Main validation
main() {
    echo "═══════════════════════════════════════"
    echo "   ZFS + ZFSBootMenu Setup Validator"
    echo "═══════════════════════════════════════"

    header "Core System"
    ROOT_DATASET=$(check_root_on_zfs)
    check_boot_directory
    ESP_PATH=$(check_esp_mount)

    header "ZFS Configuration"
    POOL=$(check_zfs_pool)
    check_bootfs_property "$POOL"
    check_zbm_properties "$ROOT_DATASET"

    header "ZFSBootMenu"
    check_zbm_config
    check_zbm_images "${ESP_PATH:-/efi}"
    check_uefi_entry

    header "Kernel Locations"
    check_kernel_locations "${ESP_PATH:-/efi}"

    header "Snapshots & Automation"
    check_snapshots "$ROOT_DATASET"
    check_pacman_hooks
    check_helper_scripts
    check_scrub_timer "$POOL"

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
