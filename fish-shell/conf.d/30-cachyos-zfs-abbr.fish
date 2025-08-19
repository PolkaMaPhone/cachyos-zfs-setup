# ZFS abbreviations for cachyos-zfs-setup
# Defines helpful abbreviations for ZFS commands

# Exit early if ZFS helpers or abbreviations are disabled
if set -q CACHYOS_ZFS_DISABLE; or set -q CACHYOS_ZFS_DISABLE_ABBR
    exit 0
end

# Helper function to define abbreviations in an idempotent way
function __cachyos_zfs_define_abbr
    set -l abbr_name $argv[1]
    set -l abbr_cmd $argv[2..-1]
    
    # Only define if not already set
    if not abbr --query $abbr_name >/dev/null 2>&1
        abbr $abbr_name $abbr_cmd
    end
end

# Define ZFS abbreviations
__cachyos_zfs_define_abbr zls zfs-list-snapshots
__cachyos_zfs_define_abbr zsi zfs-list-snapshots
__cachyos_zfs_define_abbr zcs zfs-config-show
__cachyos_zfs_define_abbr ztc zfs-be-test-clone
__cachyos_zfs_define_abbr zbi zfs-be-info --all
__cachyos_zfs_define_abbr zspace zfs-space
__cachyos_zfs_define_abbr zfs-mount-info findmnt -no SOURCE /

# Clean up helper function
functions --erase __cachyos_zfs_define_abbr