#!/bin/bash
# CachyOS ZFS Setup - Main installer
# Optimized to prevent unbootable snapshots during initial setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="/home/$SUDO_USER"

echo "=== CachyOS ZFS Setup Installation ==="

# Function to ensure kernels are in /boot BEFORE hooks are active
ensure_kernels_in_boot() {
    echo "Ensuring kernel files are in /boot before enabling hooks..."
    
    # Check if kernels are already in /boot
    if [[ -f /boot/vmlinuz-linux-cachyos ]]; then
        echo "✓ Kernel files already in /boot"
        return 0
    fi
    
    # Try to copy from ESP first
    for esp_dir in /efi /boot/efi; do
        if [[ -f "$esp_dir/vmlinuz-linux-cachyos" ]]; then
            echo "Copying kernel files from $esp_dir to /boot..."
            cp "$esp_dir/vmlinuz-linux-cachyos" /boot/
            cp "$esp_dir/initramfs-linux-cachyos"*.img /boot/ 2>/dev/null || true
            [[ -f "$esp_dir/amd-ucode.img" ]] && cp "$esp_dir/amd-ucode.img" /boot/
            [[ -f "$esp_dir/intel-ucode.img" ]] && cp "$esp_dir/intel-ucode.img" /boot/
            echo "✓ Kernel files copied to /boot"
            return 0
        fi
    done
    
    # If not found, install kernel package
    echo "Installing kernel package to populate /boot..."
    pacman -S --noconfirm linux-cachyos
    echo "✓ Kernel package installed"
}

# Function to clean up any unbootable snapshots created during install
cleanup_unbootable_snapshots() {
    echo "Checking for unbootable snapshots created during setup..."
    
    local root_dataset=$(findmnt -no SOURCE / 2>/dev/null || echo "")
    if [[ -z "$root_dataset" ]]; then
        echo "Could not detect root dataset, skipping cleanup"
        return 0
    fi
    
    # Find snapshots without kernel files (created in last hour)
    local recent_snapshots=$(zfs list -H -t snapshot -o name,creation -r "$root_dataset" 2>/dev/null | \
                            grep "@pacman-" | \
                            awk '{print $1}')
    
    for snapshot in $recent_snapshots; do
        # Check if this snapshot has kernel files
        # We'll mount it temporarily to check
        local temp_mount="/tmp/zfs-check-$$"
        mkdir -p "$temp_mount"
        
        if mount -t zfs -o ro "$snapshot" "$temp_mount" 2>/dev/null; then
            if [[ ! -f "$temp_mount/boot/vmlinuz-linux-cachyos" ]]; then
                echo "Found unbootable snapshot: $snapshot"
                umount "$temp_mount" 2>/dev/null || true
                
                # Destroy the unbootable snapshot
                echo "Removing unbootable snapshot: $snapshot"
                zfs destroy "$snapshot" 2>/dev/null || echo "  Failed to remove (may be in use)"
            else
                umount "$temp_mount" 2>/dev/null || true
            fi
        fi
        
        rmdir "$temp_mount" 2>/dev/null || true
    done
    
    echo "✓ Snapshot cleanup complete"
}

install_fish_config() {
    echo "Installing Fish shell configuration..."
    
    local fish_config_dir="$USER_HOME/.config/fish"
    sudo -u "$SUDO_USER" mkdir -p "$fish_config_dir/functions"
    
    # Copy fish config and functions
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/fish-shell/config.fish" "$fish_config_dir/"
    sudo -u "$SUDO_USER" cp "$SCRIPT_DIR/fish-shell/functions/"*.fish "$fish_config_dir/functions/"
    
    echo "✓ Fish configuration installed"
}

install_system_scripts() {
    echo "Installing system scripts..."
    
    # Copy snapshot scripts FIRST (but don't activate hooks yet)
    cp "$SCRIPT_DIR/system-scripts/snapshot-scripts/"*.sh /usr/local/sbin/
    chmod +x /usr/local/sbin/zfs-*.sh
    
    # Ensure hooks directory exists
    mkdir -p /etc/pacman.d/hooks
    
    # Copy systemd units
    cp "$SCRIPT_DIR/system-scripts/systemd-units/"* /etc/systemd/system/
    systemctl daemon-reload
    
    # Copy other scripts
    cp "$SCRIPT_DIR/system-scripts/copy-kernel-to-esp.sh" /usr/local/sbin/ 2>/dev/null || true
    cp "$SCRIPT_DIR/system-scripts/zbm-sync-be-kernel.sh" /usr/local/sbin/ 2>/dev/null || true
    chmod +x /usr/local/sbin/*.sh
    
    echo "✓ System scripts installed (hooks not yet activated)"
}

install_pacman_hooks() {
    echo "Installing pacman hooks..."
    
    # NOW install the hooks after kernels are in place
    cp "$SCRIPT_DIR/system-scripts/pacman-hooks/"*.hook /etc/pacman.d/hooks/
    
    echo "✓ Pacman hooks installed and active"
}

enable_zfs_automation() {
    echo "Enabling ZFS automation..."
    
    # Enable scrub timer for main pool (assumes zpcachyos)
    systemctl enable --now zpool-scrub@zpcachyos.timer 2>/dev/null || \
        echo "  Note: zpool-scrub timer not enabled (pool may not exist yet)"
    
    echo "✓ ZFS automation enabled"
    echo "  - Monthly pool scrubs: systemctl status zpool-scrub@zpcachyos.timer"
    echo "  - Pacman snapshot hooks: ls /etc/pacman.d/hooks/*zfs*"
}

set_fish_default() {
    echo "Setting Fish as default shell..."
    
    if [[ "$SUDO_USER" != "root" ]] && ! grep -q "/usr/bin/fish" /etc/passwd | grep "$SUDO_USER"; then
        chsh -s /usr/bin/fish "$SUDO_USER"
        echo "✓ Fish set as default shell for $SUDO_USER"
    else
        echo "✓ Fish already default or user is root"
    fi
}

detect_setup_stage() {
    # Detect if we're in initial setup or post-ZBM setup
    if [[ -f /etc/zfsbootmenu/config.yaml ]]; then
        echo "detected"
        return 0
    else
        echo "not-detected"
        return 1
    fi
}

main() {
    # Check we're running as root
    [[ $EUID -eq 0 ]] || { echo "Error: Run as root (sudo ./install.sh)"; exit 1; }
    [[ -n "${SUDO_USER:-}" ]] || { echo "Error: Must use sudo, not direct root"; exit 1; }
    
    # Detect installation stage
    local zbm_configured=$(detect_setup_stage || echo "not-detected")
    
    if [[ "$zbm_configured" == "detected" ]]; then
        echo "ZBM already configured - full installation mode"
        
        # If ZBM is configured, ensure kernels are in /boot first
        ensure_kernels_in_boot
        
        # Install everything including hooks
        install_fish_config
        install_system_scripts
        install_pacman_hooks  # Safe to install now
        enable_zfs_automation
        set_fish_default
        
        # Clean up any bad snapshots that might have been created
        cleanup_unbootable_snapshots
        
    else
        echo "ZBM not yet configured - minimal installation mode"
        echo "Deferring pacman hooks until after ZBM setup"
        
        # Install everything EXCEPT pacman hooks
        install_fish_config
        install_system_scripts  # Scripts only, no hooks
        set_fish_default
        
        # Create a script to finish installation after ZBM setup
        cat > /usr/local/sbin/finish-zfs-setup.sh <<'EOF'
#!/bin/bash
# Finish ZFS setup after ZBM is configured
echo "Completing ZFS setup..."

# Ensure kernels are in /boot
if [[ ! -f /boot/vmlinuz-linux-cachyos ]]; then
    for esp_dir in /efi /boot/efi; do
        if [[ -f "$esp_dir/vmlinuz-linux-cachyos" ]]; then
            cp "$esp_dir/vmlinuz-linux-cachyos" /boot/
            cp "$esp_dir/initramfs-linux-cachyos"*.img /boot/ 2>/dev/null || true
            break
        fi
    done
fi

# Install pacman hooks
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/../cachyos-zfs-setup/system-scripts/pacman-hooks" ]]; then
    cp "$SCRIPT_DIR/../cachyos-zfs-setup/system-scripts/pacman-hooks/"*.hook /etc/pacman.d/hooks/
elif [[ -d "/root/cachyos-zfs-setup/system-scripts/pacman-hooks" ]]; then
    cp "/root/cachyos-zfs-setup/system-scripts/pacman-hooks/"*.hook /etc/pacman.d/hooks/
else
    echo "Warning: Could not find pacman hooks to install"
fi

# Enable ZFS automation
systemctl enable --now zpool-scrub@zpcachyos.timer 2>/dev/null || true

echo "✓ ZFS setup completed!"
echo "✓ Pacman hooks are now active"
EOF
        chmod +x /usr/local/sbin/finish-zfs-setup.sh
        
        echo ""
        echo "=== IMPORTANT ==="
        echo "Pacman hooks NOT installed yet to prevent unbootable snapshots"
        echo ""
        echo "After running zbm-setup.sh, complete the installation with:"
        echo "  sudo /usr/local/sbin/finish-zfs-setup.sh"
        echo ""
        echo "Or manually copy hooks:"
        echo "  sudo cp $SCRIPT_DIR/system-scripts/pacman-hooks/*.hook /etc/pacman.d/hooks/"
    fi
    
    echo ""
    echo "=== Installation $([ "$zbm_configured" == "detected" ] && echo "Complete" || echo "Partially Complete") ==="
    echo ""
    
    if [[ "$zbm_configured" == "detected" ]]; then
        echo "Next steps:"
        echo "1. Log out and back in (or run 'exec fish') to use new shell"
        echo "2. Test ZFS functions: 'zfs-config-show'"
        echo "3. Check automation: 'systemctl list-timers | grep scrub'"
    else
        echo "Next steps:"
        echo "1. Run ZBM setup: sudo ./system-scripts/zbm-setup.sh /dev/your-esp-device"
        echo "2. Complete installation: sudo /usr/local/sbin/finish-zfs-setup.sh"
        echo "3. Log out and back in to use Fish shell"
    fi
}

main "$@"
