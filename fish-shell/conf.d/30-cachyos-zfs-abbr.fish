# CachyOS ZFS Abbreviations
# Defines convenient abbreviations for ZFS helper functions
# Can be disabled by setting CACHYOS_ZFS_DISABLE=1 or CACHYOS_ZFS_DISABLE_ABBR=1

if not set -q CACHYOS_ZFS_DISABLE; and not set -q CACHYOS_ZFS_DISABLE_ABBR
    # ZFS function abbreviations - only define if not already present
    if not abbr -q zls
        abbr zls zfs-list-snapshots
    end
    
    if not abbr -q zsi  
        abbr zsi zfs-list-snapshots
    end
    
    if not abbr -q zcs
        abbr zcs zfs-config-show
    end
    
    if not abbr -q ztc
        abbr ztc zfs-be-test-clone
    end
    
    if not abbr -q zbi
        abbr zbi zfs-be-info --all
    end
    
    if not abbr -q zspace
        abbr zspace zfs-space
    end
    
    if not abbr -q zfs-mount-info
        abbr zfs-mount-info findmnt -no SOURCE /
    end
end