#!/bin/bash
# validate-setup.sh - Verify ZFS+ZBM installation

set -euo pipefail

# Color helpers
pass() { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m✗\033[0m %s\n" "$*"; }
info() { printf "\033[1;34mℹ\033[0m %s\n" "$*"; }

echo "=== ZFS + ZBM Setup Validation ==="
echo

ERRORS=0

# Check 1: Root on ZFS
if findmnt -no FSTYPE / | grep -qx zfs; then
    pass "Root filesystem on ZFS"
    ROOT_DS=$(findmnt -no SOURCE /)
    info "Boot environment: $ROOT_DS"
else
    fail "Root filesystem NOT on ZFS"
    ((ERRORS++))
fi

# Check 2: ESP mounted
if findmnt -t vfat /efi &>/dev/null; then
    pass "ESP mounted at /efi"
elif findmnt -t vfat /boot/efi &>/dev/null; then
    pass "ESP mounted at /boot/efi"
else
    fail "ESP not mounted"
    ((ERRORS++))
fi

# Check 3: Kernel in /boot
if ls /boot/vmlinuz* &>/dev/null; then
    pass "Kernel files in /boot"
    info "Kernel: $(ls /boot/vmlinuz* | head -1)"
else
    fail "No kernel in /boot"
    ((ERRORS++))
fi

# Check 4: ZBM images
if ls /efi/EFI/ZBM/*.EFI &>/dev/null 2>&1; then
    pass "ZFSBootMenu images present"
elif ls /boot/efi/EFI/ZBM/*.EFI &>/dev/null 2>&1; then
    pass "ZFSBootMenu images present"
else
    fail "No ZFSBootMenu images found"
    ((ERRORS++))
fi

# Check 5: Snapshots
if zfs list -t snapshot 2>/dev/null | grep -q '@pacman-'; then
    pass "Pacman snapshots working"
    COUNT=$(zfs list -t snapshot | grep -c '@pacman-')
    info "Found $COUNT pacman snapshot(s)"
else
    fail "No pacman snapshots found"
    info "Try: sudo pacman -S --reinstall zlib"
    ((ERRORS++))
fi

# Check 6: Boot environments
if [[ -n "${ROOT_DS:-}" ]]; then
    BE_ROOT="${ROOT_DS%/root}"
    BE_COUNT=$(zfs list -r "${BE_ROOT%/*}" 2>/dev/null | grep -c '/root$' || echo 0)
    if [[ $BE_COUNT -gt 0 ]]; then
        pass "Found $BE_COUNT boot environment(s)"
    fi
fi

# Check 7: Hooks installed
HOOKS=(
    "/etc/pacman.d/hooks/00-zfs-pre-snapshot.hook"
    "/etc/pacman.d/hooks/99-zfs-prune-snapshots.hook"
    "/etc/pacman.d/hooks/90-generate-zbm.hook"
)

HOOKS_OK=true
for hook in "${HOOKS[@]}"; do
    if [[ ! -f "$hook" ]]; then
        HOOKS_OK=false
        break
    fi
done

if $HOOKS_OK; then
    pass "Pacman hooks installed"
else
    fail "Some pacman hooks missing"
    ((ERRORS++))
fi

# Check 8: UEFI entry
if efibootmgr 2>/dev/null | grep -q "ZFSBootMenu"; then
    pass "ZFSBootMenu UEFI entry present"
else
    fail "No ZFSBootMenu UEFI entry"
    info "Run: sudo efibootmgr -c -d /dev/sdX -p Y -L ZFSBootMenu -l '\\EFI\\ZBM\\ZFSBootMenu.EFI'"
    ((ERRORS++))
fi

echo
echo "==================================="
if [[ $ERRORS -eq 0 ]]; then
    echo "✅ All checks passed!"
else
    echo "❌ $ERRORS check(s) failed"
    echo "Please review errors above"
fi
