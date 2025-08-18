function zfs-config-show --description 'Show current ZFS environment configuration'
    echo "=== ZFS Configuration ==="
    echo "Root Pool:        $ZFS_ROOT_POOL"
    echo "Root Dataset:     $ZFS_ROOT_DATASET"
    echo "Home Dataset:     $ZFS_HOME_DATASET"
    echo "Var Cache:        $ZFS_VARCACHE_DATASET"
    echo "Var Log:          $ZFS_VARLOG_DATASET"
    echo "BE Root:          $ZFS_BE_ROOT"
    echo
    echo "=== Current Status ==="

    if test -n "$ZFS_ROOT_POOL"
        echo "Pool Status:"
        zpool status $ZFS_ROOT_POOL 2>/dev/null || echo "  Pool not found or not imported"
    end

    if test -n "$ZFS_ROOT_DATASET"
        echo "Root Dataset:"
        zfs list $ZFS_ROOT_DATASET 2>/dev/null || echo "  Dataset not found"
    end
end
