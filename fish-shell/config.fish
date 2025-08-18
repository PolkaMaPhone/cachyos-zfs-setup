source /usr/share/cachyos-fish-config/cachyos-config.fish

##
# --- Abbreviations ---
abbr zls zfs-list-snapshots
abbr zsi zfs-list-snapshots
abbr zcs zfs-config-show
abbr ztc zfs-be-test-clone
abbr zbi zfs-be-info --all
abbr zspace zfs-space
abbr zfs-mount-info findmnt -no SOURCE /
# --- End Abbreviations ---
##

##
# --- ZFS Command Options ---
# Output exact commands when calling a function?
set -g ZFS_SHOW_COMMANDS true  # or false to hide by default

# ZFS Environment Variables
set -gx ZFS_ROOT_POOL "zpcachyos"
set -gx ZFS_ROOT_DATASET "zpcachyos/ROOT/cos/root"
set -gx ZFS_HOME_DATASET "zpcachyos/ROOT/cos/home"
set -gx ZFS_VARCACHE_DATASET "zpcachyos/ROOT/cos/varcache"
set -gx ZFS_VARLOG_DATASET "zpcachyos/ROOT/cos/varlog"
set -gx ZFS_BE_ROOT "zpcachyos/ROOT"
# --- End ZFS Command Options ---

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

# Added by LM Studio CLI (lms)
set -gx PATH $PATH $HOME/.lmstudio/bin
# End of LM Studio CLI section

##
# --- SSH Section ---
# Ensure an ssh-agent connection.
# This stays in config.fish because it needs to run on shell startup
function __ensure_ssh_agent --description 'Point to systemd ssh-agent if available'
    set -l sock "$XDG_RUNTIME_DIR/ssh-agent.socket"

    # If systemd is around, ensure the service is up
    if command -sq systemctl
        systemctl --user is-active --quiet ssh-agent.service; or \
            systemctl --user start ssh-agent.service 2>/dev/null
    end

    # If the systemd socket exists, export it (remove any shadowing global)
    if test -S $sock
        set -eg SSH_AUTH_SOCK
        set -Ux SSH_AUTH_SOCK $sock
    else
        # Last-resort fallback (e.g., TTY without systemd --user)
        ssh-agent -c | source
    end
end
__ensure_ssh_agent
#--- End SSH Section ---
##
