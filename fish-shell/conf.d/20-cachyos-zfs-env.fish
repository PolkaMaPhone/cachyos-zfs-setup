# ZFS environment variables for cachyos-zfs-setup
# Sets default ZFS environment variables only if not already set

# Exit early if ZFS helpers are disabled
if set -q CACHYOS_ZFS_DISABLE
    exit 0
end

# ZFS Environment Variables - set only if not already defined
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

# ZFS Command Options - set only if not already defined
if not set -q ZFS_SHOW_COMMANDS
    set -g ZFS_SHOW_COMMANDS true
end