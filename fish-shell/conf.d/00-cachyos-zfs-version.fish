# CachyOS ZFS Helpers Version Export
# Exports version information for the ZFS helper functions
# Can be disabled by setting CACHYOS_ZFS_DISABLE=1

if not set -q CACHYOS_ZFS_DISABLE
    set -gx CACHYOS_ZFS_HELPERS_VERSION 1.0.0
end