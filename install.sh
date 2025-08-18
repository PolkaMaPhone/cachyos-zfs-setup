#!/bin/bash
# CachyOS ZFS Setup - Main installer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="/home/$SUDO_USER"

echo "=== CachyOS ZFS Setup Installation ==="

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
    
    # Copy snapshot scripts
    cp "$SCRIPT_DIR/system-scripts/snapshot-scripts/"*.sh /usr/local/sbin/
    chmod +x /usr/local/sbin/zfs-*.sh
    
    # Copy pacman hooks
    cp "$SCRIPT_DIR/system-scripts/pacman-hooks/"*.hook /etc/pacman.d/hooks/
    
    # Copy systemd units
    cp "$SCRIPT_DIR/system-scripts/systemd-units/"* /etc/systemd/system/
    systemctl daemon-reload
    
    # Copy other scripts
    cp "$SCRIPT_DIR/system-scripts/copy-kernel-to-esp.sh" /usr/local/sbin/
    cp "$SCRIPT_DIR/system-scripts/zbm-sync-be-kernel.sh" /usr/local/sbin/
    chmod +x /usr/local/sbin/*.sh
    
    echo "✓ System scripts installed"
}

enable_zfs_automation() {
    echo "Enabling ZFS automation..."
    
    # Enable scrub timer for main pool (assumes zpcachyos)
    systemctl enable --now zpool-scrub@zpcachyos.timer
    
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

main() {
    # Check we're running as root
    [[ $EUID -eq 0 ]] || { echo "Error: Run as root (sudo ./install.sh)"; exit 1; }
    [[ -n "${SUDO_USER:-}" ]] || { echo "Error: Must use sudo, not direct root"; exit 1; }
    
    install_fish_config
    install_system_scripts  
    enable_zfs_automation
    set_fish_default
    
    echo "=== Installation Complete ==="
    echo ""
    echo "Next steps:"
    echo "1. Log out and back in (or run 'exec fish') to use new shell"
    echo "2. Test ZFS functions: 'zfs-config-show'"
    echo "3. Check automation: 'systemctl list-timers | grep scrub'"
    echo ""
    echo "For full ZFS/ZBM setup on new system, run:"
    echo "  sudo ./system-scripts/zbm-setup.sh /dev/your-esp-device"
}

main "$@"
