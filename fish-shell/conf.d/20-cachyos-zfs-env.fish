# CachyOS ZFS Environment Defaults  
# Sets ZFS environment variables only if not already set by user
# Can be disabled by setting CACHYOS_ZFS_DISABLE=1

if not set -q CACHYOS_ZFS_DISABLE
    # Output exact commands when calling a function?
    if not set -q ZFS_SHOW_COMMANDS
        set -g ZFS_SHOW_COMMANDS true  # or false to hide by default
    end

    # ZFS Environment Variables - only set if not already defined
    if not set -q ZFS_ROOT_POOL
        set -gx ZFS_ROOT_POOL "zpcachyos"
    end
    
    if not set -q ZFS_ROOT_DATASET
        set -gx ZFS_ROOT_DATASET "zpcachyos/ROOT/cos/root"
    end
    
    if not set -q ZFS_HOME_DATASET
        set -gx ZFS_HOME_DATASET "zpcachyos/ROOT/cos/home"
    end
    
    if not set -q ZFS_VARCACHE_DATASET
        set -gx ZFS_VARCACHE_DATASET "zpcachyos/ROOT/cos/varcache"
    end
    
    if not set -q ZFS_VARLOG_DATASET
        set -gx ZFS_VARLOG_DATASET "zpcachyos/ROOT/cos/varlog"
    end
    
    if not set -q ZFS_BE_ROOT
        set -gx ZFS_BE_ROOT "zpcachyos/ROOT"
    end
end