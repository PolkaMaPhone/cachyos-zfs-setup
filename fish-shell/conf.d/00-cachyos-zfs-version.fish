# cachyos-zfs-setup version information
# This snippet sets version information and respects disable flags

# Exit early if ZFS helpers are disabled
if set -q CACHYOS_ZFS_DISABLE
    exit 0
end

# Read version from VERSION file
set -l version_file (dirname (status --current-filename))/../../VERSION
if test -f $version_file
    set -gx CACHYOS_ZFS_HELPERS_VERSION (cat $version_file | string trim)
else
    set -gx CACHYOS_ZFS_HELPERS_VERSION "1.0.0"
end