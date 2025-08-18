function zfs-list-boot-envs --description 'List ZFS boot environments'
    set -l options 'h/help' 's/snapshots' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-list-boot-envs [options]"
        echo "  -s/--snapshots   Include snapshots for each BE"
        echo "  -q/--quiet       Don't show the executed command"
        echo "  -h/--help        Show this help"
        echo ""
        echo "Current BE root: $ZFS_BE_ROOT"
        return
    end

    if test -z "$ZFS_BE_ROOT"
        echo "Error: ZFS_BE_ROOT environment variable not set"
        return 1
    end

    set -l cmd
    if set -q _flag_snapshots
        set cmd "zfs list -t all -r $ZFS_BE_ROOT -o name,type,used,refer,mountpoint"
    else
        set cmd "zfs list -r $ZFS_BE_ROOT -o name,used,avail,refer,mountpoint"
    end

    # Show the command being executed (unless quiet)
    if not set -q _flag_quiet
        set_color blue
        echo "# $cmd"
        set_color normal
    end

    eval $cmd
end
